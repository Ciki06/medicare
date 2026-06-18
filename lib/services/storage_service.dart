import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadProfilePicture(String uid, Uint8List imageBytes) async {
    final ref = _storage.ref().child('profile_pictures/$uid.jpg');
    await ref.putData(imageBytes);
    return await ref.getDownloadURL();
  }

  Future<String> uploadMedicationImage(String medId, Uint8List imageBytes) async {
    final ref = _storage.ref().child('medication_images/$medId.jpg');
    final metadata = SettableMetadata(contentType: 'image/jpeg');
    await ref.putData(imageBytes, metadata);
    return await ref.getDownloadURL();
  }
}
