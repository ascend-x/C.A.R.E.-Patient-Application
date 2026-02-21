import 'dart:convert';
import 'package:health_wallet/core/config/constants/app_constants.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

/// Model for a patient registered in the Care-X EMR.
class CareXPatient {
  final int id;
  final String name;
  final int age;
  final String walletAddress;

  const CareXPatient({
    required this.id,
    required this.name,
    required this.age,
    required this.walletAddress,
  });

  factory CareXPatient.fromJson(Map<String, dynamic> json) => CareXPatient(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? 'Unknown',
        age: (json['age'] as num?)?.toInt() ?? 0,
        walletAddress: json['wallet_address'] as String? ?? '',
      );
}

/// Model for a vitals record from the Care-X EMR.
class CareXVitals {
  final int? id;
  final double? bpm;
  final double? spo2;
  final double? temperature;
  final String? sessionAddress;
  final String? ipfsHash;
  final bool? isCritical;
  final String? timestamp;

  const CareXVitals({
    this.id,
    this.bpm,
    this.spo2,
    this.temperature,
    this.sessionAddress,
    this.ipfsHash,
    this.isCritical,
    this.timestamp,
  });

  factory CareXVitals.fromJson(Map<String, dynamic> json) {
    // timestamp is stored as a Float (Unix epoch seconds) in SQLite
    final rawTs = json['timestamp'];
    String? timestampStr;
    if (rawTs is num) {
      timestampStr = DateTime.fromMillisecondsSinceEpoch(
        (rawTs.toDouble() * 1000).toInt(),
      ).toIso8601String();
    } else if (rawTs is String) {
      timestampStr = rawTs;
    }

    return CareXVitals(
      id: (json['id'] as num?)?.toInt(),
      bpm: (json['bpm'] as num?)?.toDouble(),
      spo2: (json['spo2'] as num?)?.toDouble(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      sessionAddress: json['session_address'] as String?,
      ipfsHash: json['ipfs_hash'] as String?,
      isCritical: json['is_critical'] as bool?,
      timestamp: timestampStr,
    );
  }
}

/// Model for a medical document from the Care-X EMR.
/// DB schema: id, patient_wallet, file_name, description, is_secure, timestamp
class CareXDocument {
  final int id;
  final String patientWallet;
  final String documentType;
  final String? title;
  final String? ipfsHash;
  final String? timestamp;

  const CareXDocument({
    required this.id,
    required this.patientWallet,
    required this.documentType,
    this.title,
    this.ipfsHash,
    this.timestamp,
  });

  factory CareXDocument.fromJson(Map<String, dynamic> json) {
    // Actual DB columns: file_name, description — map to our model
    final fileName = json['file_name'] as String?;
    final description = json['description'] as String?;
    // Try standard fields too for forward compatibility
    final docType =
        json['document_type'] as String? ?? fileName ?? 'medical_record';
    final title = json['title'] as String? ?? fileName ?? description;

    return CareXDocument(
      id: (json['id'] as num).toInt(),
      patientWallet: json['patient_wallet'] as String? ?? '',
      documentType: docType,
      title: title,
      ipfsHash: json['ipfs_hash'] as String?,
      timestamp: json['timestamp'] as String?,
    );
  }
}

/// HTTP client for the Care-X EMR FastAPI backend (http://HOST_IP:8000/api/v1).
///
/// Exposed endpoints used by this app:
/// - GET  /patients/                          → list all patients
/// - GET  /patients/by-wallet/{wallet}        → get patient by wallet
/// - GET  /patients/{id}/vitals/              → get vitals for patient
/// - GET  /patients/by-wallet/{wallet}/documents → get documents
/// - POST /documents/share                    → grant access
/// - POST /documents/revoke                   → revoke access
@lazySingleton
class CareXApiService {
  final String _base = AppConstants.careXApiBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  // ─── Patient endpoints ──────────────────────────────────────────────────────

  Future<List<CareXPatient>> getAllPatients() async {
    final res =
        await http.get(Uri.parse('$_base/patients/'), headers: _headers);
    _checkStatus(res);
    final data = jsonDecode(res.body) as List;
    return data
        .map((e) => CareXPatient.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CareXPatient?> getPatientByWallet(String walletAddress) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/patients/by-wallet/$walletAddress'),
        headers: _headers,
      );
      if (res.statusCode == 404) return null;
      _checkStatus(res);
      return CareXPatient.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ─── Vitals endpoints ───────────────────────────────────────────────────────

  Future<List<CareXVitals>> getVitalsForPatient(int patientId) async {
    final res = await http.get(
      Uri.parse('$_base/patients/$patientId/vitals/'),
      headers: _headers,
    );
    _checkStatus(res);
    final data = jsonDecode(res.body) as List;
    return data
        .map((e) => CareXVitals.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Document access endpoints ──────────────────────────────────────────────

  Future<List<CareXDocument>> getDocumentsByWallet(
    String walletAddress, {
    String? viewerWallet,
  }) async {
    final uri = Uri.parse('$_base/patients/by-wallet/$walletAddress/documents')
        .replace(
            queryParameters:
                viewerWallet != null ? {'viewer_wallet': viewerWallet} : null);
    final res = await http.get(uri, headers: _headers);
    _checkStatus(res);
    final data = jsonDecode(res.body) as List;
    return data
        .map((e) => CareXDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Grant [recipientWallet] access to [docIds].
  Future<void> shareDocuments({
    required List<int> docIds,
    required String recipientWallet,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/documents/share'),
      headers: _headers,
      body: jsonEncode({
        'doc_ids': docIds,
        'recipient_wallet': recipientWallet,
      }),
    );
    _checkStatus(res);
  }

  /// Revoke access for [recipientWallet] to ALL documents.
  Future<void> revokeDocumentAccess(String recipientWallet) async {
    final res = await http.post(
      Uri.parse('$_base/documents/revoke'),
      headers: _headers,
      body: jsonEncode({
        'recipient_wallet': recipientWallet,
        'doc_ids': <int>[],
      }),
    );
    _checkStatus(res);
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  void _checkStatus(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('CareX API error ${res.statusCode}: ${res.body}');
    }
  }
}
