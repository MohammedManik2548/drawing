import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:ui' as ui;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print('Error initializing Firebase: $e');
  }
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Multiplayer Drawing App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(),
    );
  }
}



class GameController extends GetxController {
  var players = [].obs;
  var isLoading = false.obs;
  final GlobalKey globalKey = GlobalKey();

  // Firebase Firestore reference
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Start the game by assigning parts to players
  void startGame(String gameId) async {
    isLoading(true);

    // Mock assignment, you can randomize this
    players.value = [
      {'player_id': 'user1', 'part': 'head'},
      {'player_id': 'user2', 'part': 'body'},
    ];

    // Save initial game data to Firebase
    await firestore.collection('games').doc(gameId).set({
      'players': players.map((e) => {
        'player_id': e['player_id'],
        'part': e['part'],
        'drawing_url': ''
      }).toList(),
      'status': 'in_progress'
    });

    isLoading(false);
  }

  // Submit a player's drawing
  Future<void> submitDrawing(List<Offset?> points, String part, String playerId) async {
    isLoading(true);

    // Convert drawing to an image or points to be stored (same as before)
    final String imageUrl = await uploadDrawing(points, playerId, part);

    // Update Firestore with the drawing URL
    await firestore.collection('games').doc('gameId').update({
      'players': FieldValue.arrayUnion([{
        'player_id': playerId,
        'part': part,
        'drawing_url': imageUrl,
      }])
    });

    isLoading(false);
  }

  // Function to upload the drawing to Firebase Storage
  Future<String> uploadDrawing(List<Offset?> points, String playerId, String part) async {
    // Create a RepaintBoundary and a corresponding render object
    final boundary = await _capturePng(points);

    if (boundary == null) return '';

    // Convert boundary to a PNG image
    final imageBytes = await _boundaryToBytes(boundary);

    // Create Firebase Storage reference
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('drawings/$playerId-$part.png');

    // Upload image data to Firebase Storage
    final uploadTask = await storageRef.putData(imageBytes);

    // Get and return the download URL
    final imageUrl = await uploadTask.ref.getDownloadURL();
    return imageUrl;
  }

  // Capture the drawing canvas and return RenderRepaintBoundary
  Future<RenderRepaintBoundary?> _capturePng(List<Offset?> points) async {
    final boundary = globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    return boundary;
  }

  // Convert the boundary to PNG bytes
  Future<Uint8List> _boundaryToBytes(RenderRepaintBoundary boundary) async {
    // Generate an image from the canvas with desired dimensions
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);

    // Convert the image to bytes (PNG format)
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // Widget to render the drawing on the screen for capturing
  Widget buildDrawingCanvas(List<Offset?> points) {
    return RepaintBoundary(
      key: globalKey,
      child: CustomPaint(
        painter: CanvasPainter(points),
        size: Size.infinite,
      ),
    );
  }
}



class DrawingCanvas extends StatelessWidget {
  final String playerId;
  final String part;

  DrawingCanvas({required this.playerId, required this.part});

  final GameController gameController = Get.find<GameController>();

  @override
  Widget build(BuildContext context) {
    List<Offset?> points = [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Draw $part'),
        actions: [
          Obx(() => gameController.isLoading.value
              ? CircularProgressIndicator()
              : IconButton(
            icon: Icon(Icons.save),
            onPressed: () {
              gameController.submitDrawing(points, part, playerId);
            },
          )),
        ],
      ),
      body: GestureDetector(
        onPanUpdate: (details) {
          points.add(details.localPosition);
        },
        onPanEnd: (details) {
          points.add(null); // End of line
        },
        child: CustomPaint(
          painter: CanvasPainter(points),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class CanvasPainter extends CustomPainter {
  final List<Offset?> points;
  CanvasPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}



class CombinedDrawingScreen extends StatelessWidget {
  final GameController gameController = Get.find<GameController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Combined Drawing'),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: gameController.firestore.collection('games').doc('gameId').get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final players = snapshot.data!['players'];
          return Stack(
            children: players.map<Widget>((player) {
              return Positioned(
                child: Image.network(player['drawing_url']),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}



class HomeScreen extends StatelessWidget {
  final GameController gameController = Get.put(GameController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Multiplayer Drawing App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Obx(() => gameController.isLoading.value
                ? CircularProgressIndicator()
                : ElevatedButton(
              onPressed: () {
                // Start game and assign parts
                gameController.startGame('gameId');

                // Navigate to DrawingCanvas for this player (part assignment needed)
                Get.to(() => DrawingCanvas(playerId: 'user1', part: 'head'));
              },
              child: Text('Start Drawing'),
            )),
          ],
        ),
      ),
    );
  }
}