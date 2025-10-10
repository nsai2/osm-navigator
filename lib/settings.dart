
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  static const route = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _ttsRate = 0.47;
  double _ttsPitch = 1.0;
  String _mapChoice = 'street';
  String _provider = 'OSM Street';
  final _customUrlCtl = TextEditingController();

  String _appVersion = '';
  int _buildCode = 0;

  final _presets = const {
    'OSM Street': {
      'type': 'raster',
      'url': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      'attribution': '© OpenStreetMap contributors'
    },
    'Satellite (ESRI)': {
      'type': 'raster',
      'url': 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'attribution': '© Esri, Maxar, Earthstar Geographics, and the GIS User Community'
    },
    'OpenTopoMap': {
      'type': 'raster',
      'url': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
      'attribution': 'Map data © OpenStreetMap contributors, SRTM | Map style © OpenTopoMap (CC-BY-SA)'
    },
    'Carto Light': {
      'type': 'raster',
      'url': 'https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
      'attribution': '© CARTO'
    },
    'Carto Dark': {
      'type': 'raster',
      'url': 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
      'attribution': '© CARTO'
    }
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final pi = await PackageInfo.fromPlatform();
    setState(() {
      _ttsRate = sp.getDouble('tts_rate') ?? 0.47;
      _ttsPitch = sp.getDouble('tts_pitch') ?? 1.0;
      _mapChoice = sp.getString('map_choice') ?? 'street';
      _provider = sp.getString('map_provider') ?? 'OSM Street';
      _customUrlCtl.text = sp.getString('custom_style_url') ?? '';
      _appVersion = pi.version;
      _buildCode = int.tryParse(pi.buildNumber) ?? 0;
    });
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('tts_rate', _ttsRate);
    await sp.setDouble('tts_pitch', _ttsPitch);
    await sp.setString('map_choice', _mapChoice);
    await sp.setString('map_provider', _provider);
    await sp.setString('custom_style_url', _customUrlCtl.text.trim());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ρυθμίσεις')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Φωνητικές οδηγίες (TTS)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Ταχύτητα'), Text(_ttsRate.toStringAsFixed(2)),
          ]),
          Slider(min: 0.2, max: 1.0, divisions: 16, value: _ttsRate, onChanged: (v) => setState(()=>_ttsRate=v)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Τονικότητα'), Text(_ttsPitch.toStringAsFixed(2)),
          ]),
          Slider(min: 0.7, max: 1.3, divisions: 12, value: _ttsPitch, onChanged: (v) => setState(()=>_ttsPitch=v)),
          const SizedBox(height: 24),
          const Text('Επιλογή Χάρτη', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          RadioListTile<String>(value: 'street', groupValue: _mapChoice, title: const Text('Vector Street (MapLibre demo)'), onChanged: (v)=>setState(()=>_mapChoice=v!)),
          RadioListTile<String>(value: 'raster', groupValue: _mapChoice, title: const Text('Raster (OSM, Satellite, Topo, κ.λπ.)'), onChanged: (v)=>setState(()=>_mapChoice=v!)),
          const SizedBox(height: 16),
          const Text('Έτοιμα Styles', style: TextStyle(fontWeight: FontWeight.w600)),
          DropdownButtonFormField<String>(
            value: _provider,
            items: _presets.keys.map((k)=>DropdownMenuItem(value:k, child: Text(k))).toList(),
            onChanged: (v)=>setState(()=>_provider=v!),
          ),
          const SizedBox(height: 16),
          const Text('Custom Raster URL (προαιρετικό)', style: TextStyle(fontWeight: FontWeight.w600)),
          TextField(
            controller: _customUrlCtl,
            decoration: const InputDecoration(
              labelText: 'π.χ. https://server/tiles/{z}/{x}/{y}.png',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Center(child: Text('SAITIS NAV • v18 (build: $_buildCode)', style: TextStyle(color: Colors.grey))),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Αποθήκευση')),
        ],
      ),
    );
  }
}
