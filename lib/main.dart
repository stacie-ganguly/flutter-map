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
  MaplibreMapController? _controller;
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

  Future<void> _onMapCreated(MaplibreMapController controller) async {
    _controller = controller;

    final routeUrl = '$baseUrl:8000/geojson/routes.json';
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
        );
      } catch (e) {
        debugPrint("Error adding start-markers source/layer: $e");
      }
    }

    _controller?.moveCamera(
      CameraUpdate.newLatLngZoom(LatLng(45.5335, -122.7331), 14),
    );
  }

  double _distanceBetween(LatLng a, LatLng b) {
    const double earthRadius = 6371000;
    final double dLat = _degreesToRadians(b.latitude - a.latitude);
    final double dLon = _degreesToRadians(b.longitude - a.longitude);
    final double lat1 = _degreesToRadians(a.latitude);
    final double lat2 = _degreesToRadians(b.latitude);

    final double aVal =
        sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final double c = 2 * atan2(sqrt(aVal), sqrt(1 - aVal));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  double _distancePointToLineSegment(LatLng p, LatLng a, LatLng b) {
    double x0 = p.longitude, y0 = p.latitude;
    double x1 = a.longitude, y1 = a.latitude;
    double x2 = b.longitude, y2 = b.latitude;

    double dx = x2 - x1;
    double dy = y2 - y1;

    if (dx == 0 && dy == 0) {
      // a == b case
      return _distanceBetween(p, a);
    }

    double t = ((x0 - x1) * dx + (y0 - y1) * dy) / (dx * dx + dy * dy);
    t = t.clamp(0, 1);

    double projX = x1 + t * dx;
    double projY = y1 + t * dy;

    LatLng projection = LatLng(projY, projX);

    return _distanceBetween(p, projection);
  }

  Future<void> _onMapClick(Point<double> point, LatLng coordinates) async {
    debugPrint("Map tapped at: $coordinates");

    if (_controller == null || _routesGeoJson == null) return;

    const double tapThresholdMeters = 20; // How close the tap must be to count

    // We'll find the first trail feature whose geometry is close enough
    Map<String, dynamic>? tappedFeature;

    for (final feature in _routesGeoJson!['features']) {
      final geometry = feature['geometry'];
      if (geometry == null) continue;

      if (geometry['type'] == 'LineString') {
        final coords = geometry['coordinates'] as List<dynamic>;

        // Check each segment of the LineString
        for (int i = 0; i < coords.length - 1; i++) {
          final start = coords[i];
          final end = coords[i + 1];

          LatLng startPoint = LatLng(start[1], start[0]);
          LatLng endPoint = LatLng(end[1], end[0]);

          double dist = _distancePointToLineSegment(
            coordinates,
            startPoint,
            endPoint,
          );

          if (dist <= tapThresholdMeters) {
            tappedFeature = feature;
            break;
          }
        }

        if (tappedFeature != null) break;
      }
    }

    if (tappedFeature != null) {
      setState(() {
        _selectedFeature = tappedFeature;
      });

      await _removeHighlightLayer();

      final validFeature = {
        "type": "Feature",
        "geometry": _selectedFeature?['geometry'],
        "properties": _selectedFeature?['properties'] ?? {},
      };

      try {
        await _controller!.addSource(
          'highlight-source',
          GeojsonSourceProperties(
            data: {
              "type": "FeatureCollection",
              "features": [validFeature],
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
    } else {
      setState(() {
        _selectedFeature = null;
      });
      await _removeHighlightLayer();
    }
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
