import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/mall_database_service.dart';
import '../engine/ecef_engine.dart';
import '../engine/bearing_engine.dart';

class MallExplorerScreen extends StatefulWidget {
  final MallDatabaseService mallService;
  final GeodeticCoords? userCoords;
  final Function(String mallId) onSelectActiveMall;
  final VoidCallback? onBackClicked;
  final String userEmail;
  final VoidCallback? onLogout;

  const MallExplorerScreen({
    super.key,
    required this.mallService,
    required this.userCoords,
    required this.onSelectActiveMall,
    this.onBackClicked,
    this.userEmail = '',
    this.onLogout,
  });

  @override
  State<MallExplorerScreen> createState() => _MallExplorerScreenState();
}

class _MallExplorerScreenState extends State<MallExplorerScreen> {
  List<MallMetadata> _malls = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedCityFilter = 'ALL';
  final Map<String, double> _downloadProgress = {};
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMalls();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMalls() async {
    setState(() => _isLoading = true);
    final list = await widget.mallService.getMallsList();
    if (mounted) {
      setState(() {
        _malls = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _autoDetectAndDownloadNearestMall() async {
    if (widget.userCoords == null) return;
    setState(() => _isLoading = true);

    final nearest = widget.mallService.findNearestMall(widget.userCoords!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('GPS Auto-Detecting... Found ${nearest.name}'),
          backgroundColor: const Color(0xFF2563EB),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }

    await widget.mallService.autoDownloadAndActivateNearestMall(
      widget.userCoords!,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _downloadProgress[nearest.id] = p;
          });
        }
      },
    );

    _downloadProgress.remove(nearest.id);
    await _loadMalls();
    widget.onSelectActiveMall(nearest.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-downloaded & Activated map for ${nearest.name}!'),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  Future<void> _startDownload(MallMetadata mall) async {
    setState(() {
      _downloadProgress[mall.id] = 0.05;
    });

    await widget.mallService.downloadMallPackage(mall.id, (progress) {
      if (mounted) {
        setState(() {
          _downloadProgress[mall.id] = progress;
        });
      }
    });

    if (mounted) {
      setState(() {
        _downloadProgress.remove(mall.id);
      });
    }

    await _loadMalls();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${mall.name} map downloaded successfully!'),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  Future<void> _activateMall(MallMetadata mall) async {
    await widget.mallService.setActiveMall(mall.id);
    await _loadMalls();
    widget.onSelectActiveMall(mall.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Activated ${mall.name} map for real navigation.'),
          backgroundColor: const Color(0xFF2563EB),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _malls.where((m) {
      final q = _searchQuery.toLowerCase();
      final matchesQuery =
          m.name.toLowerCase().contains(q) ||
          m.city.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q);
      final matchesCity =
          _selectedCityFilter == 'ALL' ||
          m.city.toUpperCase().contains(_selectedCityFilter);
      return matchesQuery && matchesCity;
    }).toList();

    if (widget.userCoords != null) {
      filtered.sort((a, b) {
        final distA = haversineDistance(
          widget.userCoords!,
          GeodeticCoords(
            latitude: a.latitude,
            longitude: a.longitude,
            height: widget.userCoords!.height,
          ),
        );
        final distB = haversineDistance(
          widget.userCoords!,
          GeodeticCoords(
            latitude: b.latitude,
            longitude: b.longitude,
            height: widget.userCoords!.height,
          ),
        );
        return distA.compareTo(distB);
      });
    }

    final cities = ['ALL', 'COLOMBO', 'KANDY'];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Modern Header Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (widget.onBackClicked != null)
                          Container(
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                LucideIcons.arrowLeft,
                                color: Color(0xFF0F172A),
                                size: 18,
                              ),
                              onPressed: widget.onBackClicked,
                            ),
                          ),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Explore Malls',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_malls.length} Shopping Malls',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Auto-detect GPS button
                        GestureDetector(
                          onTap: _autoDetectAndDownloadNearestMall,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x222563EB),
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.navigation,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'GPS Auto',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.onLogout != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: widget.onLogout,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFBFDBFE),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    LucideIcons.userCheck,
                                    size: 13,
                                    color: Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    widget.userEmail.isNotEmpty
                                        ? widget.userEmail.split('@').first
                                        : 'User',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Icon(
                                    LucideIcons.logOut,
                                    size: 13,
                                    color: Color(0xFFEF4444),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar & Filter Chips Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search malls, cities, or categories...',
                        hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13.5,
                        ),
                        prefixIcon: const Icon(
                          LucideIcons.search,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(LucideIcons.x, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // City Filter Chips
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: cities.map((city) {
                                final isSelected = _selectedCityFilter == city;
                                final label = city == 'ALL'
                                    ? 'All Cities'
                                    : city;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedCityFilter = city;
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF2563EB)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                        boxShadow: isSelected
                                            ? const [
                                                BoxShadow(
                                                  color: Color(0x332563EB),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 3),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _loadMalls,
                          icon: const Icon(
                            LucideIcons.refreshCw,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          tooltip: 'Refresh Mall List',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 14)),

            // Loading state
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                ),
              )
            // Empty state
            else if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          LucideIcons.map,
                          size: 40,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No mall map found',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Try searching another city or clearing your search query',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                              _selectedCityFilter = 'ALL';
                            });
                          },
                          icon: const Icon(LucideIcons.rotateCcw, size: 14),
                          label: const Text('Reset Search'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            // Mall Cards 2-Column Grid
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.68,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final mall = filtered[index];
                    final isDownloading = _downloadProgress.containsKey(
                      mall.id,
                    );
                    final progress = _downloadProgress[mall.id] ?? 0.0;

                    double? distKm;
                    if (widget.userCoords != null) {
                      final meters = haversineDistance(
                        widget.userCoords!,
                        GeodeticCoords(
                          latitude: mall.latitude,
                          longitude: mall.longitude,
                          height: widget.userCoords!.height,
                        ),
                      );
                      distKm = meters / 1000.0;
                    }

                    return Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: mall.isActive
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFE2E8F0),
                          width: mall.isActive ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: mall.isActive
                                ? const Color(0x1F2563EB)
                                : const Color(0x0A000000),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Hero Image / Visual Header
                          Expanded(
                            flex: 5,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.asset(
                                    'assets/images/mall_bg.jpg',
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (
                                          context,
                                          error,
                                          stackTrace,
                                        ) => Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: mall.isActive
                                                  ? [
                                                      const Color(0xFF1E40AF),
                                                      const Color(0xFF3B82F6),
                                                    ]
                                                  : [
                                                      const Color(0xFF334155),
                                                      const Color(0xFF64748B),
                                                    ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                                // Dark Gradient Overlay
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.25),
                                          Colors.black.withValues(alpha: 0.70),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Top Left: Rating Badge
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.65,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          mall.rating,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        const Icon(
                                          LucideIcons.star,
                                          color: Color(0xFFFDE047),
                                          size: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Top Right: Active Badge
                                if (mall.isActive)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF16A34A),
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x4416A34A),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            LucideIcons.checkCircle2,
                                            color: Colors.white,
                                            size: 10,
                                          ),
                                          SizedBox(width: 3),
                                          Text(
                                            'ACTIVE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                // Distance Tag Overlay at bottom left of image
                                if (distKm != null)
                                  Positioned(
                                    bottom: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF2563EB,
                                        ).withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        distKm < 1.0
                                            ? '${(distKm * 1000).toInt()}m away'
                                            : '${distKm.toStringAsFixed(1)}km away',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // 2. Info & Action Section
                          Expanded(
                            flex: 6,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mall.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F172A),
                                          height: 1.15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${mall.city} • ${mall.floorCount} Floors',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Action Button / Download Progress
                                  if (isDownloading) ...[
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 5,
                                            backgroundColor: const Color(
                                              0xFFE2E8F0,
                                            ),
                                            color: const Color(0xFF2563EB),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Downloading...',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                color: Color(0xFF64748B),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '${(progress * 100).toInt()}%',
                                              style: const TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF2563EB),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    if (mall.isDownloaded) ...[
                                      SizedBox(
                                        width: double.infinity,
                                        height: 32,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: mall.isActive
                                                ? const Color(0xFFDCFCE7)
                                                : const Color(0xFF2563EB),
                                            foregroundColor: mall.isActive
                                                ? const Color(0xFF15803D)
                                                : Colors.white,
                                            elevation: mall.isActive ? 0 : 1,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              side: BorderSide(
                                                color: mall.isActive
                                                    ? const Color(0xFF86EFAC)
                                                    : Colors.transparent,
                                              ),
                                            ),
                                          ),
                                          onPressed: mall.isActive
                                              ? null
                                              : () => _activateMall(mall),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                mall.isActive
                                                    ? LucideIcons.check
                                                    : LucideIcons.navigation,
                                                size: 13,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                mall.isActive
                                                    ? 'Active'
                                                    : 'Use Map',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      SizedBox(
                                        width: double.infinity,
                                        height: 32,
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFEFF6FF,
                                            ),
                                            foregroundColor: const Color(
                                              0xFF2563EB,
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFFBFDBFE),
                                            ),
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          onPressed: () => _startDownload(mall),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                LucideIcons.downloadCloud,
                                                size: 13,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${mall.packageSizeBytesMB} MB',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }, childCount: filtered.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}
