import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MapPage(),
      debugShowCheckedModeBanner: false,
      title: 'Flutter Map',
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final MaplibreMapController _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Map'),
        backgroundColor: Color.fromARGB(255, 142, 255, 119),
      ),
      body: MaplibreMap(
        // styleString:'http://localhost:8000/styles/light.json?key=de261c3add45ec4b&mobile=true',
        styleString:
            'http://10.0.2.2:8000/styles/light.json?key=de261c3add45ec4b&mobile=true',
        initialCameraPosition: const CameraPosition(
          target: LatLng(45.5231, -122.6765),
          zoom: 12,
        ),
        onMapCreated: (controller) async {
          _controller = controller;
          debugPrint("Map is ready.");
          //load the routes onto the map
          // final geoJsonUrl = 'http://localhost:8000/geojson/routes.json';
          final routeUrl = 'http://10.0.2.2:8000/geojson/routes.json';
          final routeResponse = await http.get(Uri.parse(routeUrl));

          if (routeResponse.statusCode == 200) {
            final geoJson = json.decode(routeResponse.body);

            await _controller.addSource(
              "routes",
              GeojsonSourceProperties(data: geoJson),
            );

            await _controller.addLayer(
              "routes",
              "routes-layer",
              const LineLayerProperties(
                lineColor: ["get", "stroke"],
                lineWidth: 2,
                lineJoin: "round",
                lineCap: "round",
              ),
            );
          } else {
            debugPrint("Failed to load GeoJSON: ${routeResponse.statusCode}");
          }
          //load the start markers
          final startMarkerUrl ='http://10.0.2.2:8000/geojson/start-markers.json';
          final startMarkerResponse = await http.get(Uri.parse(startMarkerUrl));

          if (startMarkerResponse.statusCode == 200) {
            final rawGeoJson = json.decode(startMarkerResponse.body);

            for (final feature in rawGeoJson['features']) {
              final coords = feature['geometry']['coordinates'];
              if (coords is List && coords.length > 2) {
                feature['geometry']['coordinates'] = [coords[0], coords[1]]; // drop Z and T
              }
            }

            final startMarkerGeoJson = rawGeoJson;

            await _controller.addSource(
              "start-markers",
              GeojsonSourceProperties(data: startMarkerGeoJson),
            );

            await _controller.addLayer(
              "start-markers",
              "start-markers-layer",
              const CircleLayerProperties(
                circleColor: Colors.red,
                circleRadius: 6,
                circleOpacity: 0.8,
              ),
            );
          } else {
            debugPrint(
              "Failed to load GeoJSON: ${startMarkerResponse.statusCode}",
            );
          }
          await _controller.moveCamera(
            CameraUpdate.newLatLngZoom(LatLng(45.5335, -122.7331), 14),
          );
        },
      ),
    );
  }
}
