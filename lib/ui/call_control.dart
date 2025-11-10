import 'package:flutter/material.dart';

class CallControls extends StatefulWidget {
  const CallControls({super.key});

  @override
  State<CallControls> createState() => CallControlsState();
}

class CallControlsState extends State<CallControls>
    with SingleTickerProviderStateMixin {
  bool? _showCallEndResult; // null: nothing, true: Yes, false: No
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleCallEnd() async {
    setState(() {
      _showCallEndResult = null;
    });
    // Show animated dialog with BounceInDown
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.black,
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 25),
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Center(
                    child: Text(
                      'Would you like end this call?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop(true);
                        },
                        icon: const Icon(Icons.phone, color: Colors.white),
                        label: const Text(
                          'End Now',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    setState(() {
      _showCallEndResult = result;
    });
    if (result == true) {
      Navigator.pop(context);
    } else {
      // Show animated No for a moment
      await Future.delayed(const Duration(milliseconds: 800));
      setState(() {
        _showCallEndResult = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Color.fromARGB((0.25 * 255).toInt(), 255, 255, 255),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // End call button: red circle, white icon
              GestureDetector(
                onTap: _handleCallEnd,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Animated Yes/No feedback after dialog
        if (_showCallEndResult != null)
          Positioned(
            top: -60,
            child: AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 400),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _showCallEndResult!
                      ? Color.fromARGB((0.9 * 255).toInt(), 76, 175, 80)
                      : Color.fromARGB((0.9 * 255).toInt(), 244, 67, 54),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showCallEndResult! ? Icons.check_circle : Icons.cancel,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _showCallEndResult! ? 'Yes' : 'No',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
