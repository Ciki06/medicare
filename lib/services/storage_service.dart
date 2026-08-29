import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadProfilePicture(String uid, Uint8List imageBytes) async {
    final ref = _storage.ref().child('profile_pictures/$uid.jpg');
    await ref.putData(imageBytes);
    return await _getDownloadUrl(ref);
  }

  Future<String> uploadMedicationImage(String medId, Uint8List imageBytes) async {
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
