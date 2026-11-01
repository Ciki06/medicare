import 'package:flutter/material.dart';

import '../models/user_model.dart';
import 'offline_image.dart';

class ProfilePicture extends StatelessWidget {
  const ProfilePicture({
    super.key,
    required this.user,
    required this.size,
    required this.backgroundColor,
    required this.iconColor,
    this.iconSize = 24,
    this.borderRadius,
    this.profileStream,
    this.imageProviderBuilder = cachedImageProvider,
  });

  final UserModel user;
  final double size;
  final Color backgroundColor;
  final Color iconColor;
  final double iconSize;
  final BorderRadius? borderRadius;
  final Stream<UserModel?>? profileStream;
  final ImageProvider Function(String url) imageProviderBuilder;

  @override
  Widget build(BuildContext context) {
    final stream = profileStream;
    if (stream == null) return _picture(user);
    // An open detail page follows the same profile as the account and list.
    return StreamBuilder<UserModel?>(
      stream: stream,
      initialData: user,
      builder: (_, snapshot) => _picture(
        snapshot.connectionState == ConnectionState.waiting
            ? snapshot.data ?? user
            : snapshot.data,
      ),
    );
  }

  Widget _picture(UserModel? profile) {
    final url = profile?.profilePicUrl?.trim();
    final image = url == null || url.isEmpty
        ? null
        : imageProviderBuilder(_photoUrl(url));
    final icon = Icon(Icons.person, color: iconColor, size: iconSize);
    final rounding = borderRadius;
    if (rounding == null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: backgroundColor,
        foregroundImage: image,
        onForegroundImageError: image == null ? null : (_, _) {},
        child: icon,
      );
    }
    final fallback = ColoredBox(color: backgroundColor, child: icon);
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: rounding,
        child: image == null
            ? fallback
            : Image(
                key: ValueKey(url),
                image: image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  static String _photoUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'firebasestorage.googleapis.com' ||
        !uri.path.startsWith('/v0/b/') ||
        uri.queryParameters['v']?.isNotEmpty == true) {
      return url;
    }
    // Older Firebase uploads may be cached under their unversioned URL.
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParametersAll,
            'v': ['profile-1'],
          },
        )
        .toString();
  }
}
