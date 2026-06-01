import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/connectivity_provider.dart';

/// Wraps [child] and slides in a "No internet" banner at the bottom of the
/// screen when the device goes offline. Automatically dismisses when
/// connectivity is restored, showing a brief "Back online" confirmation.
class NoInternetBanner extends ConsumerStatefulWidget {
  final Widget child;
  const NoInternetBanner({super.key, required this.child});

  @override
  ConsumerState<NoInternetBanner> createState() => _NoInternetBannerState();
}

class _NoInternetBannerState extends ConsumerState<NoInternetBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  bool _wasOffline = false;
  bool _showBackOnline = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleConnectivityChange(bool hasInternet) {
    if (!hasInternet) {
      // Went offline
      _wasOffline = true;
      _showBackOnline = false;
      _controller.forward();
    } else if (_wasOffline) {
      // Came back online after being offline
      _controller.reverse().then((_) {
        if (mounted) {
          setState(() => _showBackOnline = true);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showBackOnline = false);
          });
          _wasOffline = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInternet = ref.watch(hasInternetProvider);

    // React to changes (not initial load)
    ref.listen<bool>(hasInternetProvider, (_, next) {
      _handleConnectivityChange(next);
    });

    return Stack(
      children: [
        widget.child,

        // ── Offline banner ──────────────────────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SlideTransition(
            position: _slideAnimation,
            child: AnimatedOpacity(
              opacity: hasInternet ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF323232),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(50),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'No internet connection',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Back online toast ───────────────────────────────────────────────
        if (_showBackOnline)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF388E3C), // green
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: const [
                      Icon(
                        Icons.wifi_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Back online',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
