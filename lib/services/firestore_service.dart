import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import '../models/malaysian_ic.dart';
import '../models/medication_action.dart';
import '../models/medication_model.dart';
import '../models/mood_model.dart';
import '../models/refill_request.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _apiKey => DefaultFirebaseOptions.currentPlatform.apiKey;

  static String _friendlyMessage(String code) {
    switch (code) {
      case 'CONFIGURATION_NOT_FOUND':
        return 'Email/Password sign-in is not enabled. Please contact support.';
      case 'EMAIL_EXISTS':
        return 'An account with this email already exists.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email/Password sign-in is not enabled.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Please try again later.';
      case 'EMAIL_NOT_FOUND':
        return 'No account found with this email.';
      case 'INVALID_PASSWORD':
        return 'Invalid password.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'INVALID_EMAIL':
        return 'Invalid email address.';
      case 'WEAK_PASSWORD':
        return 'Password should be at least 6 characters.';
      default:
        return code;
    }
  }

  Future<String> _createFirebaseUser(String email, String password) async {
    final response = await http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey',
      ),
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final message = body['error']['message'] ?? 'Failed to create account';
      throw Exception(_friendlyMessage(message));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['localId'] as String;
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final snap = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return UserModel.fromMap(snap.docs.first.data());
  }

  Stream<List<UserModel>> getUsersByCaregiver(String caregiverId) {
    return _firestore
        .collection('users')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => UserModel.fromMap(d.data())).toList(),
        );
  }

  Stream<List<UserModel>> getPatientsByCaregiver(String caregiverId) {
    return _firestore
        .collection('users')
        .where('caregiverId', isEqualTo: caregiverId)
        .where('role', isEqualTo: 'patient')
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => UserModel.fromMap(d.data())).toList(),
        );
  }

  Future<String> createPatientAccount({
    required String name,
    required String email,
    required String password,
    required String caregiverId,
    required String icNumber,
    required String gender,
    required String phone,
    required String address,
    List<String> medicalHistory = const [],
  }) async {
    final uid = await _createFirebaseUser(email, password);
    final now = DateTime.now();
    final birthDate = MalaysianIc.birthDate(icNumber);
    final dateOfBirth = birthDate == null
        ? null
        : '${birthDate.day.toString().padLeft(2, '0')}/'
            '${birthDate.month.toString().padLeft(2, '0')}/${birthDate.year}';
    final user = UserModel(
      uid: uid,
      name: name,
      email: email,
      role: UserRole.patient,
      createdAt: now,
      caregiverId: caregiverId,
      icNumber: icNumber,
      gender: gender,
      phone: phone,
      address: address,
      dateOfBirth: dateOfBirth,
      medicalHistory: medicalHistory,
      profilePicUrl: null,
      shortId: UserModel.generateId(UserRole.patient),
    );
    await _firestore.collection('users').doc(uid).set(user.toMap());
    return uid;
  }

  Future<String> createFamilyAccount({
    required String name,
    required String email,
    required String password,
    required String caregiverId,
  }) async {
    final uid = await _createFirebaseUser(email, password);
    final user = UserModel(
      uid: uid,
      name: name,
      email: email,
      role: UserRole.family,
      createdAt: DateTime.now(),
      caregiverId: caregiverId,
      profilePicUrl: null,
      shortId: UserModel.generateId(UserRole.family),
    );
    await _firestore.collection('users').doc(uid).set(user.toMap());
    return uid;
  }

  Future<String> createPharmacistAccount({
    required String name,
    required String email,
    required String password,
    required String caregiverId,
  }) async {
    final uid = await _createFirebaseUser(email, password);
    final user = UserModel(
      uid: uid,
      name: name,
      email: email,
      role: UserRole.pharmacist,
      createdAt: DateTime.now(),
      caregiverId: caregiverId,
      profilePicUrl: null,
      shortId: UserModel.generateId(UserRole.pharmacist),
    );
    await _firestore.collection('users').doc(uid).set(user.toMap());
    return uid;
  }

  Future<String> createMedication(Medication medication) async {
    final doc = await _firestore
        .collection('medications')
        .add(medication.toMap());
    return doc.id;
  }

  Stream<List<Medication>> getMedicationsByCaregiver(String caregiverId) {
    return _firestore
        .collection('medications')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Medication.fromMap(d.id, d.data())).toList()
                ..sort(Medication.compareByTime),
        );
  }

  Stream<List<Medication>> getMedicationsByPatient(String patientId) {
    return _firestore
        .collection('medications')
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Medication.fromMap(d.id, d.data())).toList()
                ..sort(Medication.compareByTime),
        );
  }

  Future<String> createAppointment(Appointment appointment) async {
    final doc = await _firestore
        .collection('appointments')
        .add(appointment.toMap());
    return doc.id;
  }

  Future<void> updateAppointment(Appointment appointment) {
    return _firestore
        .collection('appointments')
        .doc(appointment.id)
        .update(appointment.toMap());
  }

  Future<void> updateMedication(Medication medication) {
    return _firestore
        .collection('medications')
        .doc(medication.id)
        .update(medication.toMap());
  }

  Stream<List<Appointment>> getAppointmentsByCaregiver(String caregiverId) {
    return _firestore
        .collection('appointments')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Appointment.fromMap(d.id, d.data())).toList()
                ..sort((a, b) => a.date.compareTo(b.date)),
        );
  }

  Stream<List<Appointment>> getAppointmentsByPatient(String patientId) {
    return _firestore
        .collection('appointments')
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Appointment.fromMap(d.id, d.data())).toList()
                ..sort((a, b) => a.date.compareTo(b.date)),
        );
  }

  Future<String> addMedication({
    required String caregiverId,
    required String patientId,
    required String patientName,
    required String name,
    required String type,
    required String dosage,
    required String time,
    int currentStock = 0,
    String? imageUrl,
    bool remindRefill = true,
    int remindThreshold = 5,
  }) async {
    final med = Medication(
      id: '',
      name: name,
      dosage: dosage,
      time: time,
      days: ['Daily'],
      patientId: patientId,
      patientName: patientName,
      caregiverId: caregiverId,
      type: type,
      currentStock: currentStock,
      imageUrl: imageUrl,
      remindRefill: remindRefill,
      remindThreshold: remindThreshold,
    );
    final doc = await _firestore.collection('medications').add(med.toMap());
    return doc.id;
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    data.removeWhere((_, v) => v == null);
    if (data.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(data);
    }
  }

  Future<void> cleanNullFields(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final deletes = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.value == null) {
        deletes[entry.key] = FieldValue.delete();
      }
    }
    if (deletes.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(deletes);
    }
  }

  Future<String> createRefillRequest(RefillRequest request) async {
    final doc = await _firestore
        .collection('refill_requests')
        .add(request.toMap());
    return doc.id;
  }

  Stream<List<RefillRequest>> getRefillRequestsByCaregiver(String caregiverId) {
    return _firestore
        .collection('refill_requests')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((d) => RefillRequest.fromMap(d.id, d.data()))
                  .toList()
                ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
        );
  }

  Stream<List<RefillRequest>> getRefillRequestsByPatient(String patientId) {
    return _firestore
        .collection('refill_requests')
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((d) => RefillRequest.fromMap(d.id, d.data()))
                  .toList()
                ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
        );
  }

  Stream<List<RefillRequest>> getAllRefillRequests() {
    return _firestore
        .collection('refill_requests')
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => RefillRequest.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<void> updateRefillRequestStatus(
    String requestId,
    String status,
  ) async {
    await _firestore.collection('refill_requests').doc(requestId).update({
      'status': status,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> logMedicationAction({
    required String medicationId,
    required String medicationName,
    required String patientId,
    required String action,
    int? snoozedUntil,
  }) async {
    await _firestore.collection('medication_actions').add({
      'medicationId': medicationId,
      'medicationName': medicationName,
      'patientId': patientId,
      'action': action,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'snoozedUntil': ?snoozedUntil,
    });
  }

  Stream<List<MedicationAction>> getMedicationActionsByPatient(
    String patientId,
  ) {
    return _firestore
        .collection('medication_actions')
        .where('patientId', isEqualTo: patientId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => MedicationAction.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Stream<List<MedicationAction>> getMedicationActionsByPatients(
    List<String> patientIds,
  ) {
    if (patientIds.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('medication_actions')
        .where('patientId', whereIn: patientIds.take(30).toList())
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((d) => MedicationAction.fromMap(d.id, d.data()))
                  .toList()
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        );
  }

  Future<void> updateMedicationImage(String medId, String imageUrl) async {
    await _firestore.collection('medications').doc(medId).update({
      'imageUrl': imageUrl,
    });
  }

  Future<void> updateMedicationStock(String medId, int stock) async {
    await _firestore.collection('medications').doc(medId).update({
      'currentStock': stock,
    });
  }

  Future<void> restockMedication(String medId, int amount) async {
    await _firestore.collection('medications').doc(medId).update({
      'currentStock': FieldValue.increment(amount),
    });
  }

  Future<void> deleteMedication(String medId) async {
    await _firestore.collection('medications').doc(medId).delete();
  }

  Future<void> deleteAppointment(String appointmentId) async {
    await _firestore.collection('appointments').doc(appointmentId).delete();
  }

  Future<void> saveMood({
    required String patientId,
    required int moodIndex,
    required String moodLabel,
    required String emoji,
    required String date,
  }) async {
    await _firestore.collection('moods').doc('${patientId}_$date').set({
      'patientId': patientId,
      'moodIndex': moodIndex,
      'moodLabel': moodLabel,
      'emoji': emoji,
      'date': date,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<DailyMood?> getTodayMood(String patientId, String date) {
    return _firestore
        .collection('moods')
        .where('patientId', isEqualTo: patientId)
        .where('date', isEqualTo: date)
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          return DailyMood.fromMap(snap.docs.first.id, snap.docs.first.data());
        });
  }

  Future<void> deleteMood({
    required String patientId,
    required String date,
  }) async {
    await _firestore.collection('moods').doc('${patientId}_$date').delete();
  }

  Stream<List<DailyMood>> getTodayMoodsByPatients(
    List<String> patientIds,
    String date,
  ) {
    if (patientIds.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('moods')
        .where('patientId', whereIn: patientIds.take(30).toList())
        .where('date', isEqualTo: date)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => DailyMood.fromMap(d.id, d.data())).toList(),
        );
  }
}
