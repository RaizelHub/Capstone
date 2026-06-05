import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class EmergencyAuthService {
  static final EmergencyAuthService _instance = EmergencyAuthService._internal();
  factory EmergencyAuthService() => _instance;
  EmergencyAuthService._internal();

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // Emergency access codes (in production, these should be stored securely)
  final Map<String, String> _emergencyAccessCodes = {
    'ADMIN001': 'Emergency Administrator',
    'SAFETY01': 'Safety Officer',
    'MAINT01': 'Maintenance Supervisor',
  };

  // Temporary emergency codes (valid for limited time)
  final Map<String, Map<String, dynamic>> _temporaryAccessCodes = {};

  /// Verify emergency access code
  bool verifyEmergencyCode(String code) {
    // Check permanent codes
    if (_emergencyAccessCodes.containsKey(code.toUpperCase())) {
      return true;
    }

    // Check temporary codes
    final tempCode = _temporaryAccessCodes[code.toUpperCase()];
    if (tempCode != null) {
      final expiryTime = tempCode['expiry'] as DateTime;
      if (DateTime.now().isBefore(expiryTime)) {
        return true;
      } else {
        // Remove expired code
        _temporaryAccessCodes.remove(code.toUpperCase());
      }
    }

    return false;
  }

  /// Get the name associated with an emergency code
  String getAuthorizedPersonName(String code) {
    final upperCode = code.toUpperCase();
    
    // Check permanent codes
    if (_emergencyAccessCodes.containsKey(upperCode)) {
      return _emergencyAccessCodes[upperCode]!;
    }

    // Check temporary codes
    final tempCode = _temporaryAccessCodes[upperCode];
    if (tempCode != null) {
      final expiryTime = tempCode['expiry'] as DateTime;
      if (DateTime.now().isBefore(expiryTime)) {
        return tempCode['name'] as String;
      }
    }

    return 'Unknown';
  }

  /// Generate a temporary emergency access code
  String generateTemporaryCode(String authorizedPersonName, Duration validFor) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final hash = sha256.convert(utf8.encode('$authorizedPersonName$timestamp')).toString();
    final tempCode = 'TEMP${hash.substring(0, 6).toUpperCase()}';
    
    _temporaryAccessCodes[tempCode] = {
      'name': authorizedPersonName,
      'expiry': DateTime.now().add(validFor),
      'generated_at': DateTime.now(),
    };

    return tempCode;
  }

  /// Show emergency authentication dialog
  Future<String?> showEmergencyAuthDialog(BuildContext context) async {
    String? enteredCode;
    String? authorizedPerson;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text(
                'EMERGENCY ACCESS',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This action requires emergency authorization.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              TextField(
                onChanged: (value) => enteredCode = value,
                decoration: InputDecoration(
                  labelText: 'Emergency Access Code',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.security),
                ),
                obscureText: true,
                textCapitalization: TextCapitalization.characters,
              ),
              SizedBox(height: 8),
              Text(
                'Contact your system administrator for emergency access codes.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                if (enteredCode != null && verifyEmergencyCode(enteredCode!)) {
                  authorizedPerson = getAuthorizedPersonName(enteredCode!);
                  Navigator.of(context).pop(authorizedPerson);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Invalid emergency access code'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('AUTHORIZE'),
            ),
          ],
        );
      },
    );
  }

  /// Log emergency access attempt
  Future<void> logEmergencyAccess({
    required String code,
    required bool successful,
    required String action,
    String? deviceId,
  }) async {
    try {
      await _dbRef.child('emergency_access_logs').push().set({
        'code_used': code,
        'successful': successful,
        'action': action,
        'device_id': deviceId,
        'timestamp': DateTime.now().toIso8601String(),
        'unix_timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('Error logging emergency access: $e');
    }
  }

  /// Clean up expired temporary codes
  void cleanupExpiredCodes() {
    final now = DateTime.now();
    _temporaryAccessCodes.removeWhere((code, data) {
      final expiry = data['expiry'] as DateTime;
      return now.isAfter(expiry);
    });
  }

  /// Get all active emergency codes (for admin purposes)
  Map<String, Map<String, dynamic>> getActiveEmergencyCodes() {
    cleanupExpiredCodes();
    
    final activeCodes = <String, Map<String, dynamic>>{};
    
    // Add permanent codes
    _emergencyAccessCodes.forEach((code, name) {
      activeCodes[code] = {
        'name': name,
        'type': 'permanent',
        'expiry': null,
      };
    });

    // Add temporary codes
    _temporaryAccessCodes.forEach((code, data) {
      activeCodes[code] = {
        'name': data['name'],
        'type': 'temporary',
        'expiry': data['expiry'],
        'generated_at': data['generated_at'],
      };
    });

    return activeCodes;
  }
}
