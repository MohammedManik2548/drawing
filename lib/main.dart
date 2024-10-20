import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';

void main() {
  runApp(DrawingApp());
}

class DrawingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drawing App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: DrawingCanvas(),
    );
  }
}

class DrawingCanvas extends StatefulWidget {
  @override
  _DrawingCanvasState createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<Offset?> points = [];
  Database? database;
  GlobalKey _globalKey = GlobalKey(); // Use GlobalKey to capture the widget size

  @override
  void initState() {
    super.initState();
    initializeDatabase(); // Initialize the SQLite database
  }

  // Initialize SQLite database
  Future<void> initializeDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'drawing_app.db');
    database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute('CREATE TABLE drawings(id INTEGER PRIMARY KEY AUTOINCREMENT, image BLOB)');
      },
    );
  }

  // Save the full canvas drawing based on widget size
  Future<void> saveFullDrawing(BuildContext context) async {
    RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final size = boundary.size; // Capture the actual widget size
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height)); // Use dynamic size
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    // Paint the points (lines) on the canvas
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), size.height.toInt()); // Create image using widget size
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png); // Convert to PNG
    final pngBytes = byteData!.buffer.asUint8List(); // Get bytes to store

    // Insert the image data into SQLite as a BLOB
    await database?.insert('drawings', {'image': pngBytes});

    // Display a success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Full drawing saved!')),
    );
  }

  // Retrieve all saved drawings from SQLite
  Future<List<Map<String, dynamic>>> loadAllDrawings() async {
    return await database?.query('drawings') ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter Drawing Canvas'),
      ),
      body: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            points.add(details.localPosition);
          });
        },
        onPanEnd: (details) {
          setState(() {
            points.add(null);
          });
        },
        child: RepaintBoundary( // Use RepaintBoundary to capture the widget
          key: _globalKey, // Attach GlobalKey
          child: CustomPaint(
            painter: CanvasPainter(points),
            child: Container(),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'saveFullDrawing',
            child: Icon(Icons.save),
            onPressed: () async {
              await saveFullDrawing(context);
              setState(() {
                points.clear(); // Clear canvas after saving
              });
            },
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'viewDrawings',
            child: Icon(Icons.image),
            onPressed: () async {
              List<Map<String, dynamic>> drawings = await loadAllDrawings();
              if (drawings.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DrawingListScreen(drawings: drawings),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No saved drawings!')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class CanvasPainter extends CustomPainter {
  final List<Offset?> points;

  CanvasPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

// Screen to display the list of saved drawings
class DrawingListScreen extends StatelessWidget {
  final List<Map<String, dynamic>> drawings;

  DrawingListScreen({required this.drawings});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Drawings'),
      ),
      body: ListView.builder(
        itemCount: drawings.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text('Drawing #${drawings[index]['id']}'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ImageScreen(imageData: drawings[index]['image']),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Screen to display a single saved drawing
class ImageScreen extends StatelessWidget {
  final Uint8List imageData;

  ImageScreen({required this.imageData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Drawing'),
      ),
      body: Center(
        child: Image.memory(imageData), // Display image from Uint8List data
      ),
    );
  }
}
