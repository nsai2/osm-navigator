
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OSMNavigatorApp());
}

class OSMNavigatorApp extends StatelessWidget {
  const OSMNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OSM Navigator',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _map;
  Symbol? _userSymbol;
  Line? _routeLine;
  Symbol? _destSymbol;

  Position? _lastPos;
  StreamSubscription<Position>? _posStream;
  bool _navigating = false;
  List<RouteStep> _steps = [];
  double _remainingMeters = 0;
  double _remainingSeconds = 0;

  final _searchCtrl = TextEditingController();
  List<SearchResult> _suggestions = [];

  static const _osmRasterStyle = '''{
    "version": 8,
    "name": "OSM Raster",
    "sources": {
      "osm": {
        "type": "raster",
        "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
        "tileSize": 256,
        "attribution": "© OpenStreetMap contributors"
      }
    },
    "layers": [
      {"id": "bg", "type": "background", "paint": {"background-color": "#ffffff"}},
      {"id": "osm", "type": "raster", "source": "osm"}
    ]
  }''';

  @override
  void initState() {
    super.initState();
    _ensurePermission();
  }

  Future<void> _ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  }

  @override
  void dispose() {
    _posStream?.cancel();
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) async {
    _map = controller;
    await _moveToUser();
  }

  Future<void> _moveToUser() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _lastPos = pos;
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15.0));
      await _updateUserSymbol(LatLng(pos.latitude, pos.longitude), pos.heading);
    } catch (_) {}
  }

  Future<void> _startPositionStream() async {
    _posStream?.cancel();
    _posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2),
    ).listen((pos) {
      _lastPos = pos;
      _updateUserSymbol(LatLng(pos.latitude, pos.longitude), pos.heading);
      if (_navigating && _routeLine != null) {
        _checkProgressAndMaybeReroute();
      }
    });
  }

  Future<void> _updateUserSymbol(LatLng latLng, double heading) async {
    if (_userSymbol == null) {
      _userSymbol = await _map?.addSymbol(SymbolOptions(
        geometry: latLng,
        textField: "📍",
        textSize: 24,
        textRotate: heading,
      ));
    } else {
      await _map?.updateSymbol(_userSymbol!, SymbolOptions(geometry: latLng, textRotate: heading));
    }
  }

  Future<void> _addDestination(LatLng latLng) async {
    if (_destSymbol == null) {
      _destSymbol = await _map?.addSymbol(SymbolOptions(
        geometry: latLng,
        iconImage: "marker-15",
        textField: "DEST",
        textOffset: const Offset(0, 1.2),
      ));
    } else {
      await _map?.updateSymbol(_destSymbol!, SymbolOptions(geometry: latLng));
    }
  }

  Future<void> _routeTo(LatLng dest) async {
    if (_lastPos == null) {
      await _moveToUser();
      if (_lastPos == null) return;
    }
    final start = LatLng(_lastPos!.latitude, _lastPos!.longitude);
    await _addDestination(dest);
    final route = await fetchRoute(start, dest);
    setState(() {
      _steps = route.steps;
      _remainingMeters = route.distance;
      _remainingSeconds = route.duration;
    });
    await _drawRoute(route.polyline);
    await _map?.animateCamera(CameraUpdate.newLatLngBounds(route.bounds, left: 40, top: 160, right: 40, bottom: 200));
  }

  Future<void> _drawRoute(List<LatLng> line) async {
    if (_routeLine == null) {
      _routeLine = await _map?.addLine(LineOptions(
        geometry: line,
        lineWidth: 6,
        lineOpacity: 0.9,
      ));
    } else {
      await _map?.updateLine(_routeLine!, LineOptions(geometry: line));
    }
  }

  Future<void> _checkProgressAndMaybeReroute() async {
    if (_routeLine == null || _lastPos == null) return;
    final here = LatLng(_lastPos!.latitude, _lastPos!.longitude);
    final line = _routeLine!.options.geometry!;
    final d = _minDistanceToPolyline(here, line);
    if (d > 30) {
      await _routeTo(_destSymbol!.options.geometry!);
    } else {
      final end = line.last;
      final meters = _haversine(here, end);
      setState(() {
        _remainingMeters = math.max(0, meters);
      });
    }
  }

  double _haversine(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final la1 = _deg2rad(a.latitude);
    final la2 = _deg2rad(b.latitude);
    final h = math.sin(dLat/2)*math.sin(dLat/2) + math.cos(la1)*math.cos(la2)*math.sin(dLon/2)*math.sin(dLon/2);
    return 2*R*math.asin(math.sqrt(h));
  }
  double _deg2rad(double d) => d * math.pi / 180;

  double _minDistanceToPolyline(LatLng p, List<LatLng> line){
    double best = double.infinity;
    for (int i=0; i<line.length-1; i++){
      best = math.min(best, _distancePointToSegmentMeters(p, line[i], line[i+1]));
    }
    return best;
  }

  double _distancePointToSegmentMeters(LatLng p, LatLng a, LatLng b){
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;
    final dx = bx - ax, dy = by - ay;
    final t = ((px-ax)*dx + (py-ay)*dy) / (dx*dx + dy*dy);
    final tt = t.clamp(0.0, 1.0);
    final cx = ax + tt*dx, cy = ay + tt*dy;
    return _haversine(p, LatLng(cy, cx));
  }

  Future<void> _onMapLongPress(math.Point<double> point, LatLng latLng) async {
    await _routeTo(latLng);
  }

  @override
  Widget build(BuildContext context) {
    final km = (_remainingMeters/1000.0);
    final min = _remainingSeconds/60.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OSM Navigator'),
        actions: [
          IconButton(onPressed: _moveToUser, icon: const Icon(Icons.my_location)),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: Stack(
              children: [
                MapLibreMap(
                  styleString: _osmRasterStyle,
                  initialCameraPosition: const CameraPosition(target: LatLng(37.9838, 23.7275), zoom: 12),
                  onMapCreated: _onMapCreated,
                  compassEnabled: true,
                  onMapLongClick: _onMapLongPress,
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(_steps.isEmpty ? 'Long-press map to set destination' : _steps.first.instruction)),
                          const SizedBox(width: 12),
                          Text(km>0? '${km.toStringAsFixed(1)} km' : ''),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      FloatingActionButton.small(onPressed: (){ _map?.animateCamera(CameraUpdate.zoomIn()); }, child: const Icon(Icons.add)),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(onPressed: (){ _map?.animateCamera(CameraUpdate.zoomOut()); }, child: const Icon(Icons.remove)),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildNavBar(min),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (!_navigating){
            await _startPositionStream();
          }
          setState((){ _navigating = !_navigating; });
        },
        icon: Icon(_navigating? Icons.stop : Icons.navigation),
        label: Text(_navigating? 'Stop' : 'Start'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildSearchBar(){
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search places (Nominatim)…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: (){ _searchCtrl.clear(); setState(()=>_suggestions=[]); }),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) async {
              _suggestions = v.trim().isEmpty ? [] : await nominatimSearch(v.trim());
              setState((){});
            },
            onSubmitted: (v) async {
              final s = await nominatimSearch(v.trim());
              if (s.isNotEmpty){
                final first = s.first;
                _map?.animateCamera(CameraUpdate.newLatLngZoom(first.latLng, 15));
                await _addDestination(first.latLng);
              }
            },
          ),
        ),
        if (_suggestions.isNotEmpty)
          SizedBox(
            height: 160,
            child: ListView.builder(
              itemCount: _suggestions.length,
              itemBuilder: (c,i){
                final s = _suggestions[i];
                return ListTile(
                  leading: const Icon(Icons.place),
                  title: Text(s.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('(${s.latLng.latitude.toStringAsFixed(5)}, ${s.latLng.longitude.toStringAsFixed(5)})'),
                  onTap: () async {
                    _searchCtrl.text = s.displayName;
                    setState(()=>_suggestions=[]);
                    _map?.animateCamera(CameraUpdate.newLatLngZoom(s.latLng, 15));
                    await _addDestination(s.latLng);
                    await _routeTo(s.latLng);
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildNavBar(double minutes){
    final fmt = NumberFormat('0');
    return BottomAppBar(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            const Icon(Icons.directions_car),
            const SizedBox(width: 12),
            Expanded(child: Text(_steps.isEmpty ? 'No route' : '${_steps.length} steps · ETA ~${fmt.format(minutes)} min')),
            FilledButton(
              onPressed: () async {
                if (_destSymbol!=null){
                  await _routeTo(_destSymbol!.options.geometry!);
                }
              },
              child: const Text('Reroute'),
            )
          ],
        ),
      ),
    );
  }
}

class RouteStep {
  final String instruction;
  final double distance;
  final double duration;
  RouteStep(this.instruction, this.distance, this.duration);
}

class RouteResult {
  final double distance; // meters
  final double duration; // seconds
  final List<RouteStep> steps;
  final List<LatLng> polyline;
  final LatLngBounds bounds;
  RouteResult(this.distance, this.duration, this.steps, this.polyline, this.bounds);
}

Future<RouteResult> fetchRoute(LatLng start, LatLng end) async {
  final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson&steps=true');
  final res = await http.get(url, headers: {
    'User-Agent': 'OSMNavigator/0.1 (demo)'
  });
  if (res.statusCode != 200) {
    throw Exception('Routing failed: ${res.statusCode}');
  }
  final data = json.decode(res.body);
  final route = data['routes'][0];
  final distance = (route['distance'] as num).toDouble();
  final duration = (route['duration'] as num).toDouble();
  final coords = (route['geometry']['coordinates'] as List)
      .map<LatLng>((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
      .toList();
  final b = _computeBounds(coords);

  final legs = (route['legs'] as List);
  final steps = <RouteStep>[];
  for (final leg in legs){
    for (final st in (leg['steps'] as List)){
      final name = st['name'] ?? '';
      final maneuver = st['maneuver']?['type'] ?? 'continue';
      final modifier = st['maneuver']?['modifier'];
      final instr = _formatInstruction(maneuver, modifier, name);
      steps.add(RouteStep(instr, (st['distance'] as num).toDouble(), (st['duration'] as num).toDouble()));
    }
  }
  return RouteResult(distance, duration, steps, coords, b);
}

LatLngBounds _computeBounds(List<LatLng> pts){
  double minLat=90, maxLat=-90, minLon=180, maxLon=-180;
  for (final p in pts){
    if (p.latitude<minLat) minLat=p.latitude;
    if (p.latitude>maxLat) maxLat=p.latitude;
    if (p.longitude<minLon) minLon=p.longitude;
    if (p.longitude>maxLon) maxLon=p.longitude;
  }
  return LatLngBounds(southwest: LatLng(minLat,minLon), northeast: LatLng(maxLat,maxLon));
}

String _formatInstruction(String type, dynamic modifier, String name){
  final mod = modifier==null? '' : ' ${modifier.toString()}';
  switch (type){
    case 'turn':
      return 'Turn$mod onto $name';
    case 'merge':
      return 'Merge$mod onto $name';
    case 'roundabout':
      return 'Enter roundabout';
    case 'depart':
      return 'Head$mod on $name';
    case 'arrive':
      return 'Arrive at destination';
    default:
      return 'Continue on $name';
  }
}

class SearchResult{
  final String displayName; final LatLng latLng;
  SearchResult(this.displayName, this.latLng);
}

Future<List<SearchResult>> nominatimSearch(String query) async {
  final url = Uri.parse('https://nominatim.openstreetmap.org/search?format=jsonv2&q='+Uri.encodeQueryComponent(query)+'&limit=8');
  final res = await http.get(url, headers: {'User-Agent': 'OSMNavigator/0.1 (demo)'});
  if (res.statusCode != 200) return [];
  final data = json.decode(res.body) as List;
  return data.map((e){
    final lat = double.parse(e['lat']);
    final lon = double.parse(e['lon']);
    final name = (e['display_name'] as String);
    return SearchResult(name, LatLng(lat, lon));
  }).toList();
}
