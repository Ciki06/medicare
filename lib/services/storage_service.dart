import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> copyChatMedia(
    String url,
    String destination,
    String uid, {
    required bool voice,
  }) async {
    final source = _storage.refFromURL(url);
    final bytes = await source.getData(10 * 1024 * 1024);
    if (bytes == null) {
      throw StateError('The original attachment is unavailable.');
    }
    final metadata = await source.getMetadata();
    return uploadChatMedia(
      destination,
      uid,
      bytes,
      voice: voice,
      imageType: metadata.contentType ?? 'image/jpeg',
    );
  }

  Future<String> uploadChatMedia(
    String chatId,
    String uid,
    Uint8List bytes, {
    required bool voice,
    String imageType = 'image/jpeg',
  }) async {
    if (bytes.length > 10 * 1024 * 1024) {
      throw Exception('Attachments must be under 10 MB.');
    }
    final ref = _storage.ref(
      'chat_media/$chatId/$uid/${DateTime.now().microsecondsSinceEpoch}.${voice ? 'm4a' : 'image'}',
    );
    await ref.putData(
      bytes,
      SettableMetadata(contentType: voice ? 'audio/mp4' : imageType),
    );
    return _getDownloadUrl(ref);
  }

  Future<String> uploadProfilePicture(String uid, Uint8List imageBytes) async {
    final ref = _storage.ref().child('profile_pictures/$uid.jpg');
    await ref.putData(imageBytes);
    return await _getDownloadUrl(ref);
  }

  Future<String> uploadMedicationImage(
    String medId,
    Uint8List imageBytes,
  ) async {
    final ref = _storage.ref().child('medication_images/$medId.jpg');
    final metadata = SettableMetadata(contentType: 'image/jpeg');
    await ref.putData(imageBytes, metadata);
    return await _getDownloadUrl(ref);
  }

  Future<String> _getDownloadUrl(Reference ref) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await ref.getDownloadURL();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found' || attempt == 2) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    throw StateError('getDownloadURL failed after retries');
  }
}
