import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

ImageProvider cachedImageProvider(String url) =>
    CachedNetworkImageProvider(url, cacheManager: OfflineImage.cache);

class OfflineImage extends StatelessWidget {
  const OfflineImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
    this.loadingBuilder,
    this.zoomable = false,
  });
  final String url;
  final double? width, height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final bool zoomable;
  static final cache = CacheManager(
    Config(
      'medicare_images_v1',
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 2000,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: url,
      cacheManager: cache,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, _) => SizedBox(
        width: width,
        height: height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (context, _, error) =>
          errorBuilder?.call(context, error, null) ??
          SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: Icon(Icons.image_not_supported_outlined),
            ),
          ),
    );
    return zoomable
        ? Semantics(
            button: true,
            label: 'Enlarge medicine image',
            child: InkWell(
              onTap: () => showImageViewer(context, url),
              child: image,
            ),
          )
        : image;
  }
}

void showImageViewer(BuildContext context, String url) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Image'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: OfflineImage(url, fit: BoxFit.contain),
          ),
        ),
      ),
    ),
  );
}
