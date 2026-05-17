import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivity_and_wellbeing/services/steps_service.dart';
import 'home_screen.dart';
import 'package:provider/provider.dart';
import '../models/app_data.dart';
import '../services/hometab_service.dart';
import '../services/streak_service.dart';
import '../services/moodscreen_service.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;

  late Animation<double> _pulseAnimation;
  bool _isFinished = false;

  String loadingText = "Initializing services...";

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final appData = Provider.of<AppData>(context, listen: false);

    try {
      ///
      /// AUTH
      ///
      setState(() {
        loadingText = "Checking account...";
      });

      await Future.delayed(const Duration(milliseconds: 400));

      ///
      /// HOME DATA
      ///
      setState(() {
        loadingText = "Loading daily motivation...";
      });

      await HomeTabService.preload(appData);

      ///
      /// STEP SYSTEM
      ///
      setState(() {
        loadingText = "Starting step tracker...";
      });

      await StepsService.instance.initialize(appData);

      await Future.delayed(const Duration(milliseconds: 500));

      ///
      /// MOOD SERVICE
      ///
      ///
      setState(() {
        loadingText = "Loading mood data...";
      });

      await MoodService.instance.initialize(appData);

      await Future.delayed(const Duration(milliseconds: 500));

      ///
      /// STEP SERVICE
      ///
      ///
      ///

      setState(() {
        loadingText = "Syncing activity data...";
      });

      await StreakService.preload(appData);

      await Future.delayed(const Duration(milliseconds: 500));

      ///
      /// FINALIZATION
      ///
      setState(() {
        loadingText = "Preparing dashboard...";
      });

      await Future.delayed(const Duration(milliseconds: 500));

      ///
      /// DONE
      ///
      if (!mounted) return;

      setState(() {
        _isFinished = true;
      });
    } catch (e) {
      debugPrint("Initialization Error: $e");

      setState(() {
        loadingText = "Failed to load app";
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFinished) {
      return const HomeScreen();
    }
    
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),

      body: Stack(
        children: [
          /// TOP GLOW
          Positioned(
            top: -120,
            left: -80,
            child: _buildGlow(280, Colors.orange.withValues(alpha: 0.18)),
          ),

          /// BOTTOM GLOW
          Positioned(
            bottom: -150,
            right: -100,
            child: _buildGlow(340, Colors.deepOrange.withValues(alpha: 0.14)),
          ),

          /// CONTENT
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ///
                  /// ROTATING RING + CENTER ICON
                  ///
                  SizedBox(
                    width: 190,
                    height: 190,

                    child: Stack(
                      alignment: Alignment.center,

                      children: [
                        /// ROTATING OUTER RING
                        AnimatedBuilder(
                          animation: _rotateController,

                          builder: (_, child) {
                            return Transform.rotate(
                              angle: _rotateController.value * 2 * pi,
                              child: child,
                            );
                          },

                          child: Container(
                            width: 185,
                            height: 185,

                            decoration: BoxDecoration(
                              shape: BoxShape.circle,

                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.15),
                                width: 2.5,
                              ),

                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  blurRadius: 25,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),

                            child: Padding(
                              padding: const EdgeInsets.all(18),

                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,

                                  border: Border.all(
                                    color: Colors.deepOrange.withValues(
                                      alpha: 0.35,
                                    ),
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        /// CENTER ICON
                        ScaleTransition(
                          scale: _pulseAnimation,

                          child: Container(
                            width: 100,
                            height: 100,

                            decoration: BoxDecoration(
                              shape: BoxShape.circle,

                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,

                                colors: [Color(0xFFFFB347), Color(0xFFFF6B00)],
                              ),

                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.45),
                                  blurRadius: 30,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),

                            child: const Icon(
                              Icons.directions_walk_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  ///
                  /// TITLE
                  ///
                  const Text(
                    "Fullbright Smart System",
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 14),

                  ///
                  /// SUBTITLE
                  ///
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),

                    child: Text(
                      loadingText,
                      textAlign: TextAlign.center,

                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 15,
                        height: 1.5,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  ///
                  /// PROGRESS BAR
                  ///
                  SizedBox(
                    width: size.width * 0.60,

                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),

                      child: LinearProgressIndicator(
                        minHeight: 8,
                        backgroundColor: Colors.orange.shade100,

                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF7A00),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  ///
                  /// LOADING LABEL
                  ///
                  Text(
                    "Loading services...",
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlow(double size, Color color) {
    return Container(
      width: size,
      height: size,

      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,

        boxShadow: [BoxShadow(color: color, blurRadius: 120, spreadRadius: 40)],
      ),
    );
  }
}
