import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

void main() => runApp(const MaterialApp(
  debugShowCheckedModeBanner: false,
  title: 'SAITIS NAV',
  home: SaitisOkScreen(),
));

class SaitisOkScreen extends StatelessWidget {
  const SaitisOkScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children:[
          const ml.MaplibreMap(
            initialCameraPosition: ml.CameraPosition(target: ml.LatLng(37.9838, 23.7275), zoom: 12.0),
            styleString: 'https://demotiles.maplibre.org/style.json',
          ),
          Positioned(
            top: 50, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: const Text('SAITIS NAV — OK', style: TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}
