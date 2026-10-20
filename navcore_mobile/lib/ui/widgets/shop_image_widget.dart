import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Ultra-performant widget to display shop and venue images seamlessly.
/// Supports in-memory decoded caching for Base64 (0ms decode after 1st load),
/// persistent memory caching for Network URLs, local device files, and asset paths.
class ShopImage extends StatefulWidget {
  final String imagePathOrUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallbackWidget;

  const ShopImage({
    super.key,
    required this.imagePathOrUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallbackWidget,
  });

  // ==========================================
  // STATIC IN-MEMORY HIGH-SPEED CACHES
  // ==========================================
  static final Map<String, Uint8List> _base64Cache = {};
  static final Map<String, Uint8List> _networkCache = {};
  static final Set<String> _pendingNetworkUrls = {};
  static final Set<String> _failedKeys = {};

  /// Immediate registration of image bytes (e.g. freshly picked from phone gallery)
  static void cacheBytes(String key, Uint8List bytes) {
    final k = _generateKey(key);
    _base64Cache[k] = bytes;
  }

  /// Asynchronously pre-decode a list of shop images into memory so scrolling is 60fps
  static void prewarm(Iterable<String> imageStrings) {
    for (final raw in imageStrings) {
      final s = raw.trim();
      if (s.isEmpty || !isBase64String(s)) continue;
      _decodeBase64Fast(s);
    }
  }

  static String _generateKey(String raw) {
    final s = raw.trim();
    if (s.length <= 160) return s;
    return '${s.length}_${s.substring(0, 40)}_${s.substring(s.length - 40)}';
  }

  static bool isBase64String(String str) {
    final s = str.trim();
    if (s.startsWith('data:image/')) return true;
    if (s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('assets/') ||
        s.startsWith('file://')) {
      return false;
    }
    // High probability Base64 payload if length is substantial and not a system path
    if (s.length > 100 && !s.contains(':\\') && !s.startsWith('/')) {
      return true;
    }
    return false;
  }

  static Uint8List? _decodeBase64Fast(String raw) {
    final key = _generateKey(raw);
    final cached = _base64Cache[key];
    if (cached != null) return cached;
    if (_failedKeys.contains(key)) return null;

    try {
      final clean = raw.trim();
      final payload = clean.contains(',') ? clean.split(',').last.trim() : clean;
      final bytes = base64Decode(payload);
      _base64Cache[key] = bytes;
      return bytes;
    } catch (_) {
      _failedKeys.add(key);
      return null;
    }
  }

  @override
  State<ShopImage> createState() => _ShopImageState();
}

class _ShopImageState extends State<ShopImage> {
  Uint8List? _networkBytes;
  bool _isLoadingNetwork = false;

  @override
  void initState() {
    super.initState();
    _checkAndFetchNetworkImage();
  }

  @override
  void didUpdateWidget(covariant ShopImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imagePathOrUrl != oldWidget.imagePathOrUrl) {
      _checkAndFetchNetworkImage();
    }
  }

  void _checkAndFetchNetworkImage() {
    final clean = widget.imagePathOrUrl.trim();
    if (_isNetworkUrl(clean)) {
      final cached = ShopImage._networkCache[clean];
      if (cached != null) {
        _networkBytes = cached;
      } else if (!ShopImage._failedKeys.contains(clean) && !_isLoadingNetwork) {
        _fetchNetworkImage(clean);
      }
    }
  }

  Future<void> _fetchNetworkImage(String url) async {
    if (ShopImage._pendingNetworkUrls.contains(url)) return;
    ShopImage._pendingNetworkUrls.add(url);
    if (mounted) setState(() => _isLoadingNetwork = true);

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        ShopImage._networkCache[url] = response.bodyBytes;
        if (mounted) {
          setState(() {
            _networkBytes = response.bodyBytes;
            _isLoadingNetwork = false;
          });
        }
      } else {
        ShopImage._failedKeys.add(url);
        if (mounted) setState(() => _isLoadingNetwork = false);
      }
    } catch (_) {
      ShopImage._failedKeys.add(url);
      if (mounted) setState(() => _isLoadingNetwork = false);
    } finally {
      ShopImage._pendingNetworkUrls.remove(url);
    }
  }

  bool _isNetworkUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  bool _isLocalFile(String path) {
    if (_isNetworkUrl(path) || ShopImage.isBase64String(path)) return false;
    if (path.startsWith('assets/')) return false;
    return path.startsWith('/') ||
        path.contains(':\\') ||
        path.startsWith('file://');
  }

  String _normalizeAssetPath(String raw) {
    final clean = raw.trim();
    if (clean.startsWith('assets/')) return clean;
    if (clean.endsWith('.jpg') ||
        clean.endsWith('.png') ||
        clean.endsWith('.jpeg')) {
      return 'assets/images/shops/$clean';
    }
    return 'assets/images/shops/$clean.jpg';
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          LucideIcons.store,
          size: (widget.width != null && widget.width! < 60) ? 20 : 26,
          color: const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _buildDefaultFallback() {
    return widget.fallbackWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.storefront_rounded,
              color: Colors.white70,
              size: (widget.width != null && widget.width! < 60) ? 22 : 28,
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final clean = widget.imagePathOrUrl.trim();

    if (clean.isEmpty || clean == 'null' || clean == 'undefined' || clean == 'none') {
      return _buildDefaultFallback();
    }

    // Target downsample resolution for fast rasterization
    final targetW = widget.width != null ? (widget.width! * 2.2).round() : 220;
    final targetH = widget.height != null ? (widget.height! * 2.2).round() : 220;

    // 1. BASE64 FAST PATH (0ms when pre-cached)
    if (ShopImage.isBase64String(clean)) {
      final bytes = ShopImage._decodeBase64Fast(clean);
      if (bytes != null) {
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: targetW,
          cacheHeight: targetH,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildDefaultFallback(),
        );
      }
      return _buildDefaultFallback();
    }

    // 2. NETWORK URL FAST PATH (Cached in RAM, or instant fallback)
    if (_isNetworkUrl(clean)) {
      if (_networkBytes != null) {
        return Image.memory(
          _networkBytes!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: targetW,
          cacheHeight: targetH,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildDefaultFallback(),
        );
      }
      if (_isLoadingNetwork) {
        return _buildPlaceholder();
      }
      // Direct network load fallback with smooth placeholder
      return Image.network(
        clean,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: targetW,
        cacheHeight: targetH,
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) => _buildDefaultFallback(),
      );
    }

    // 3. LOCAL FILE PATH
    if (_isLocalFile(clean)) {
      try {
        final filePath = clean.startsWith('file://')
            ? clean.replaceFirst('file://', '')
            : clean;
        final file = File(filePath);
        if (file.existsSync()) {
          return Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            cacheWidth: targetW,
            cacheHeight: targetH,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => _buildDefaultFallback(),
          );
        }
      } catch (_) {}
      return _buildDefaultFallback();
    }

    // 4. BUNDLED ASSETS
    return Image.asset(
      _normalizeAssetPath(clean),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: targetW,
      cacheHeight: targetH,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _buildDefaultFallback(),
    );
  }
}
