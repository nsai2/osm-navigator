
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SaitisNavApp());
}

class SaitisNavApp extends StatelessWidget {
  const SaitisNavApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAITIS NAV',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2C6BED)),
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum OrientationMode { northUp, headingUp }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String _styleUrl = 'https://demotiles.maplibre.org/style.json';
  ml.MaplibreMapController? _controller;
  StreamSubscription<Position>? _posSub;
  OrientationMode _orientationMode = OrientationMode.headingUp;
  bool _following = true;
  bool _mapReady = false;
  Position? _lastPosition;
  double _lastHeading = 0.0;
  final FlutterTts _tts = FlutterTts();

  ml.Symbol? _meSymbol;
  ml.Symbol? _destSymbol;
  final String _meIcon = "me-triangle";
  final String _destIcon = "dest-flag";

  double _ttsRate = 0.47;
  double _ttsPitch = 1.0;

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _initTTS();
    _loadPrefs();
  }

  String _buildRasterStyle(String url, {String attribution = ''}) {
    final style = {
      'version': 8,
      'name': 'RasterStyle',
      'sources': {
        'raster': {
          'type': 'raster',
          'tiles': [url],
          'tileSize': 256,
          'attribution': attribution
        }
      },
      'layers': [
        {'id': 'raster', 'type': 'raster', 'source': 'raster'}
      ]
    };
    return const JsonEncoder.withIndent('  ').convert(style);
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final choice = sp.getString('map_choice') ?? 'street';
    final provider = sp.getString('map_provider') ?? 'OSM Street';
    final custom = sp.getString('custom_style_url') ?? '';
    String styleString;
    if (choice == 'street') {
      styleString = 'https://demotiles.maplibre.org/style.json';
    } else {
      String url, attribution;
      switch (provider) {
        case 'OSM Street':
          url = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
          attribution = '© OpenStreetMap contributors';
          break;
        case 'Satellite (ESRI)':
          url = 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
          attribution = '© Esri, Maxar, Earthstar Geographics, and the GIS User Community';
          break;
        case 'OpenTopoMap':
          url = 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
          attribution = 'Map data © OpenStreetMap contributors, SRTM | Map style © OpenTopoMap (CC-BY-SA)';
          break;
        case 'Carto Light':
          url = 'https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png';
          attribution = '© CARTO';
          break;
        case 'Carto Dark':
          url = 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png';
          attribution = '© CARTO';
          break;
        default:
          url = custom.isNotEmpty ? custom : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
          attribution = '';
      }
      styleString = _buildRasterStyle(url, attribution: attribution);
    }
    setState(() {
      _styleUrl = styleString;
      _ttsRate = sp.getDouble('tts_rate') ?? 0.47;
      _ttsPitch = sp.getDouble('tts_pitch') ?? 1.0;
    });
    await _tts.setSpeechRate(_ttsRate);
    await _tts.setPitch(_ttsPitch);
  }

  Future<void> _initTTS() async { await _tts.setLanguage("el-GR"); }

  Future<void> _initPermissions() async {
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied || status == LocationPermission.deniedForever) {
      status = await Geolocator.requestPermission();
    }
    if (await Geolocator.isLocationServiceEnabled()) _startPositionUpdates();
    Geolocator.getServiceStatusStream().listen((event) { if (event == ServiceStatus.enabled) _startPositionUpdates(); });
  }

  void _startPositionUpdates() {
    _posSub?.cancel();
    const settings = LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) async {
      _lastPosition = pos;
      final heading = pos.heading.isFinite ? pos.heading : _lastHeading;
      _lastHeading = heading;
      await _updateMeSymbol(pos, heading);
      if (_following && _controller != null && _mapReady) {
        await _moveCameraToUser(pos, heading, animated: true);
      }
    });
  }

  @override
  void dispose() { _posSub?.cancel(); super.dispose(); }

  void _onMapCreated(ml.MaplibreMapController controller) { _controller = controller; }

  void _onStyleLoaded() async {
    _mapReady = true;
    await _addImageFromAsset(_meIcon, 'assets/images/triangle.png');
    await _addImageFromAsset(_destIcon, 'assets/images/dest.png');
    if (_lastPosition != null) {
      await _updateMeSymbol(_lastPosition!, _lastHeading);
      await _moveCameraToUser(_lastPosition!, _lastHeading, animated: false);
    }
  }

  Future<void> _addImageFromAsset(String name, String asset) async {
    final bytes = await DefaultAssetBundle.of(context).load(asset);
    await _controller?.addImage(name, bytes.buffer.asUint8List());
  }

  Future<void> _updateMeSymbol(Position pos, double heading) async {
    if (_controller == null || !_mapReady) return;
    final latLng = ml.LatLng(pos.latitude, pos.longitude);
    if (_meSymbol == null) {
      _meSymbol = await _controller!.addSymbol(ml.SymbolOptions(
        geometry: latLng,
        iconImage: _meIcon,
        iconSize: 0.5,
        iconRotate: heading,
        iconOpacity: 0.9,
        iconAnchor: 'center',
        iconOffset: Offset(0.0, 80.0),
      ));
    } else {
      await _controller!.updateSymbol(_meSymbol!, ml.SymbolOptions(
        geometry: latLng,
        iconRotate: heading,
        iconOpacity: 0.9,
      ));
    }
  }

  Future<void> _moveCameraToUser(Position pos, double heading, {bool animated = true}) async {
    if (_controller == null) return;
    final bearing = _orientationMode == OrientationMode.headingUp ? heading : 0.0;
    final target = ml.LatLng(pos.latitude, pos.longitude);
    final update = ml.CameraUpdate.newCameraPosition(
      ml.CameraPosition(target: target, zoom: 16.5, bearing: bearing, tilt: 60.0),
    );
    if (animated) { await _controller!.animateCamera(update); } else { await _controller!.moveCamera(update); }
  }

  void _toggleOrientation() {
    setState(() {
      _orientationMode = _orientationMode == OrientationMode.headingUp ? OrientationMode.northUp : OrientationMode.headingUp;
    });
    if (_lastPosition != null) { _moveCameraToUser(_lastPosition!, _lastHeading, animated: true); }
  }

  void _recenter() {
    setState(() => _following = true);
    if (_lastPosition != null) { _moveCameraToUser(_lastPosition!, _lastHeading, animated: true); }
  }

  Future<void> _setDestination(ml.LatLng point) async {
    if (!mounted) return;
    final shouldReplace = _destSymbol == null
        ? true
        : (await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Αλλαγή προορισμού;'),
                content: const Text('Θέλεις να αντικατασταθεί ο τρέχων προορισμός με το νέο σημείο;'),
                actions: [ TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι')),
                           FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι')) ],
              ),
            )) ?? false;
    if (!shouldReplace) return;
    if (_destSymbol == null) {
      _destSymbol = await _controller?.addSymbol(ml.SymbolOptions(geometry: point, iconImage: _destIcon, iconOpacity: 0.8));
    } else {
      await _controller?.updateSymbol(_destSymbol!, ml.SymbolOptions(geometry: point, iconOpacity: 0.8));
    }
    await _tts.speak("Νέος προορισμός ορίστηκε.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ml.MaplibreMap(
            key: ValueKey(_styleUrl),
            initialCameraPosition: const ml.CameraPosition(target: ml.LatLng(37.9838, 23.7275), zoom: 12.0),
            styleString: _styleUrl,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            compassEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            onMapClick: (point, latLng) => setState(()=>_following=false),
            onMapLongClick: (point, latLng) async => _setDestination(latLng),
          ),
          // Settings button (top-left)
          Positioned(
            top: 16, left: 16,
            child: Opacity(
              opacity: 0.85,
              child: FloatingActionButton.small(
                heroTag: "settingsBtn",
                onPressed: () async {
                  final changed = await Navigator.of(context).push(MaterialPageRoute(builder: (_)=>const SettingsPage()));
                  if (changed == true) {
                    await _loadPrefs();
                    _meSymbol = null; _destSymbol = null;
                    await _addImageFromAsset(_meIcon, 'assets/images/triangle.png');
                    await _addImageFromAsset(_destIcon, 'assets/images/dest.png');
                    if (_lastPosition != null) _updateMeSymbol(_lastPosition!, _lastHeading);
                  }
                },
                child: const Icon(Icons.settings),
              ),
            ),
          ),
          // Orientation + recenter (top-right)
          Positioned(
            top: 16, right: 16,
            child: Column(
              children: [
                Opacity(
                  opacity: 0.75,
                  child: FloatingActionButton.small(
                    heroTag: "orientationBtn",
                    onPressed: _toggleOrientation,
                    child: Icon(_orientationMode == OrientationMode.headingUp ? Icons.navigation : Icons.north),
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: 0.75,
                  child: FloatingActionButton.small(
                    heroTag: "recenterBtn",
                    onPressed: _recenter,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          // Zoom (lower-right)
          Positioned(
            top: 140, right: 16,
            child: Column(
              children: [
                Opacity(
                  opacity: 0.85,
                  child: FloatingActionButton.small(
                    heroTag: "zoomInBtn",
                    onPressed: () async { if (_controller!=null) await _controller!.animateCamera(ml.CameraUpdate.zoomIn()); },
                    child: const Icon(Icons.add),
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: 0.85,
                  child: FloatingActionButton.small(
                    heroTag: "zoomOutBtn",
                    onPressed: () async { if (_controller!=null) await _controller!.animateCamera(ml.CameraUpdate.zoomOut()); },
                    child: const Icon(Icons.remove),
                  ),
                ),
              ],
            ),
          ),
          if (!_following)
            Positioned(
              bottom: 24, left: 16, right: 16,
              child: Opacity(
                opacity: 0.8,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Παρακολούθηση απενεργοποιημένη'),
                        TextButton.icon(onPressed: _recenter, icon: const Icon(Icons.my_location), label: const Text('Κέντρο')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
