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
  List<Uint8List> savedDrawings = []; // Store multiple drawings
  Database? database;
  GlobalKey _globalKey = GlobalKey();

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

  // Save individual drawing and store it in the list
  Future<void> saveIndividualDrawing(BuildContext context) async {
    RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final size = boundary.size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
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
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    savedDrawings.add(pngBytes); // Store this drawing
    setState(() {
      points.clear(); // Clear the current canvas after saving
    });

    // Display a success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Drawing saved!')),
    );
  }

  // Combine all saved drawings into one image without space between them
  Future<void> combineDrawings(BuildContext context) async {
    if (savedDrawings.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please save three drawings first!')),
      );
      return;
    }

    RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final size = boundary.size;
    final recorder = ui.PictureRecorder();

    // Total height to combine all images without space
    final double totalHeight = size.height * savedDrawings.length;

    // Create a canvas large enough to fit all images
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, totalHeight));

    // Loop over each saved drawing and place them directly below each other
    for (int i = 0; i < savedDrawings.length; i++) {
      final img = await decodeImageFromList(savedDrawings[i]);
      final double yOffset = i * size.height;  // Calculate the vertical position of each image

      // Draw each image at the calculated yOffset
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),  // Source rect for the full image
        Rect.fromLTWH(0, yOffset, size.width, size.height),  // Destination on the combined canvas
        Paint(),
      );
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), totalHeight.toInt());  // Combine images into one
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    // Save the combined image to SQLite as a single image
    await database?.insert('drawings', {'image': pngBytes});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('All drawings combined and saved!')),
    );
  }

  // // // Combine all saved drawings into one image
  // Future<void> combineDrawings(BuildContext context) async {
  //   if (savedDrawings.length < 3) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Please save three drawings first!')),
  //     );
  //     return;
  //   }
  //
  //   RenderRepaintBoundary boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  //   final size = boundary.size;
  //   final recorder = ui.PictureRecorder();
  //   final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
  //
  //   // Combine each saved drawing by drawing them onto the canvas
  //   for (int i = 0; i < savedDrawings.length; i++) {
  //     final img = await decodeImageFromList(savedDrawings[i]);
  //     canvas.drawImage(img, Offset(0, i * (size.height / 3)), Paint()); // Position each drawing
  //   }
  //
  //   final picture = recorder.endRecording();
  //   final img = await picture.toImage(size.width.toInt(), size.height.toInt());
  //   final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  //   final pngBytes = byteData!.buffer.asUint8List();
  //
  //   // Save the combined image to SQLite as a single image
  //   await database?.insert('drawings', {'image': pngBytes});
  //
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(content: Text('All drawings combined and saved!')),
  //   );
  // }

  // Retrieve the latest combined drawing from SQLite
  Future<Uint8List?> loadCombinedDrawing() async {
    final data = await database?.query(
      'drawings',
      orderBy: 'id DESC', // Get the most recent combined image
      limit: 1, // Only get the last combined image
    );

    if (data != null && data.isNotEmpty) {
      return data.first['image'] as Uint8List; // Return the image data
    }
    return null;
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
        child: RepaintBoundary(
          key: _globalKey,
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
            heroTag: 'saveIndividual',
            child: Icon(Icons.save),
            onPressed: () async {
              await saveIndividualDrawing(context);
            },
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'combineDrawings',
            child: Icon(Icons.layers),
            onPressed: () async {
              await combineDrawings(context); // Combine all saved drawings
            },
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'viewCombinedDrawing',
            child: Icon(Icons.image),
            onPressed: () async {
              Uint8List? combinedImage = await loadCombinedDrawing(); // Load the combined image

              if (combinedImage != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CombinedDrawingScreen(imageData: combinedImage),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No combined drawing found!')),
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

class CombinedDrawingScreen extends StatelessWidget {
  final Uint8List imageData;

  CombinedDrawingScreen({required this.imageData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Combined Drawing'),
      ),
      body: Center(
        child: Image.memory(imageData), // Display the combined drawing
      ),
    );
  }
}
