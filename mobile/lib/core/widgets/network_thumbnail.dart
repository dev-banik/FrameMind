import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class NetworkThumbnail extends StatelessWidget {
  const NetworkThumbnail({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.borderRadius = 12,
    this.icon = Icons.movie_creation_outlined,
  });

  final String? url;
  final double? width;
  final double? height;
  final double borderRadius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: scheme.onPrimaryContainer.withAlpha(170)),
    );

    final link = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: link == null || link.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: link,
              width: width,
              height: height,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            ),
    );
  }
}
