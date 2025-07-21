import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

const baseUrl = 'http://192.168.0.135:8000';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
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
  MapLibreMapController? _controller;
  Map<String, dynamic>? _selectedFeature;
  Map<String, dynamic>? _routesGeoJson;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Map'),
        backgroundColor: const Color.fromARGB(255, 142, 255, 119),
      ),
      body: MapLibreMap(
        rotateGesturesEnabled: true,
        styleString:
            '$baseUrl/styles/light.json?key=de261c3add45ec4b&mobile=true',
        initialCameraPosition: const CameraPosition(
          target: LatLng(45.5231, -122.6765),
          zoom: 12,
        ),
        onMapCreated: _onMapCreated,
        onMapClick: _onMapClick,
      ),
    );
  }

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;

    final routeUrl = '$baseUrl/geojson/routes.json';
    final routeResponse = await http.get(Uri.parse(routeUrl));

    if (routeResponse.statusCode == 200) {
      final geoJson = json.decode(routeResponse.body);
      _routesGeoJson = geoJson; // Save for manual hit test

      try {
        _controller?.addSource(
          "routes",
          GeojsonSourceProperties(data: geoJson),
        );
        _controller?.addLineLayer(
          "routes",
          "routes-layer",
          const LineLayerProperties(
            lineColor: ['get', 'stroke'],
            lineWidth: 2,
            lineJoin: "round",
            lineCap: "round",
          ),
          // Enables onFeatureTapped for this layer.
          // Touches will not be passed through to the onMapClick handler.
          enableInteraction: true,
        );
      } catch (e) {
        debugPrint("Error adding routes source/layer: $e");
      }
    }

    final startMarkerUrl = '$baseUrl/geojson/start-markers.json';
    final startMarkerResponse = await http.get(Uri.parse(startMarkerUrl));

    if (startMarkerResponse.statusCode == 200) {
      final rawGeoJson = json.decode(startMarkerResponse.body);

      for (final feature in rawGeoJson['features']) {
        final coords = feature['geometry']['coordinates'];
        if (coords is List && coords.length >= 2) {
          final lon = coords[0];
          final lat = coords[1];
          feature['geometry']['coordinates'] = [lon, lat];
        }
      }

      try {
        _controller?.addSource(
          "start-markers",
          GeojsonSourceProperties(data: rawGeoJson),
        );
        _controller?.addCircleLayer(
          "start-markers",
          "start-markers-layer",
          const CircleLayerProperties(
            circleColor: '#FF0000',
            circleRadius: 6,
            circleOpacity: 0.8,
            circleStrokeWidth: 1,
            circleStrokeColor: '#000000',
          ),
          enableInteraction: false,
        );
      } catch (e) {
        debugPrint("Error adding start-markers source/layer: $e");
      }
    }

    _controller?.onFeatureTapped.add((tappedFeature, pos, coords, layer) async {
      // tappedFeature is the ID of the feature that was tapped.
      // Since our only features are the routes, one of the IDs will match.
      for (final feature in _routesGeoJson!['features']) {
        if (feature['id'].toString() == tappedFeature) {
          debugPrint("Feature matched: ${feature['id']}");
          setState(() {
            _selectedFeature = feature;
          });
        }
      }

      await _removeHighlightLayer();

      try {
        await _controller!.addSource(
          'highlight-source',
          GeojsonSourceProperties(
            data: {
              "type": "FeatureCollection",
              "features": [_selectedFeature],
            },
          ),
        );
      } catch (e) {
        debugPrint("Highlight source already exists or error: $e");
      }

      try {
        await _controller!.addLineLayer(
          'highlight-source',
          'highlight-layer',
          const LineLayerProperties(
            lineColor: '#000000', // highlight color (blue)
            lineWidth: 6,
            lineJoin: 'round',
            lineCap: 'round',
          ),
        );
      } catch (e) {
        debugPrint("Highlight layer already exists or error: $e");
      }
    });

    _controller?.moveCamera(
      CameraUpdate.newLatLngZoom(LatLng(45.5335, -122.7331), 14),
    );
  }

  // Since clicks on routes aren't passed through, any call to this function
  // means the user clicked outside of a route and we should remove the highlight.
  Future<void> _onMapClick(Point<double> point, LatLng coordinates) async {
    setState(() {
      _selectedFeature = null;
    });
    await _removeHighlightLayer();
  }

  Future<void> _removeHighlightLayer() async {
    try {
      await _controller?.removeLayer('highlight-layer');
    } catch (e) {
      debugPrint('Error removing highlight-layer: $e');
    }
    try {
      await _controller?.removeSource('highlight-source');
    } catch (e) {
      debugPrint('Error removing highlight-source: $e');
    }
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }
}
