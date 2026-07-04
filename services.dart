/// AI Civic Guardian - Services & State Management
///
/// Contains: API configuration, HTTP services for auth and complaints,
/// and the two ChangeNotifier providers that hold app state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Central place to configure the backend URL.
/// - Android emulator -> your machine: 10.0.2.2
/// - iOS simulator -> your machine: localhost
/// - Physical device -> your computer's LAN IP, e.g. 192.168.1.10
/// - Deployed backend -> its real https:// URL
class ApiConfig {
  static const String baseUrl = 'http://10.0.2.2:8000';
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

String _extractError(http.Response response, String fallback) {
  try {
    final body = jsonDecode(response.body);
    if (body is Map && body['detail'] != null) return body['detail'].toString();
  } catch (_) {
    // response wasn't JSON - fall through to fallback message
  }
  return fallback;
}

// ============================================================================
// AUTH SERVICE
// ============================================================================

class AuthService {
  static const _tokenKey = 'auth_token';

  Future<String> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode != 200) {
      throw ApiException(_extractError(response, 'Login failed'));
    }
    final token = jsonDecode(response.body)['access_token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    return token;
  }

  Future<void> register({
    required String name,
    required String email,
    String? phone,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'phone': phone, 'password': password}),
    );
    if (response.statusCode != 201) {
      throw ApiException(_extractError(response, 'Registration failed'));
    }
  }

  Future<AppUser> fetchCurrentUser(String token) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw ApiException(_extractError(response, 'Could not load profile'));
    }
    return AppUser.fromJson(jsonDecode(response.body));
  }

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}

// ============================================================================
// COMPLAINT SERVICE
// ============================================================================

class ComplaintService {
  Future<Complaint> createComplaint({
    required String token,
    required String title,
    required String description,
    required String category,
    required String severity,
    required double latitude,
    required double longitude,
    String? address,
    String? landmark,
    bool isAnonymous = false,
    String? contactNumber,
    List<File> images = const [],
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/complaints');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    request.fields['title'] = title;
    request.fields['description'] = description;
    request.fields['category'] = category;
    request.fields['severity'] = severity;
    request.fields['latitude'] = latitude.toString();
    request.fields['longitude'] = longitude.toString();
    request.fields['is_anonymous'] = isAnonymous.toString();
    if (address != null) request.fields['address'] = address;
    if (landmark != null) request.fields['landmark'] = landmark;
    if (contactNumber != null) request.fields['contact_number'] = contactNumber;

    for (final image in images) {
      request.files.add(await http.MultipartFile.fromPath('images', image.path));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 201) {
      throw ApiException(_extractError(response, 'Failed to submit complaint'));
    }
    return Complaint.fromJson(jsonDecode(response.body));
  }

  Future<List<Complaint>> listComplaints({
    required String token,
    String? category,
    String? status,
    bool mineOnly = false,
  }) async {
    final queryParams = <String, String>{};
    if (category != null) queryParams['category'] = category;
    if (status != null) queryParams['status'] = status;
    if (mineOnly) queryParams['mine_only'] = 'true';

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/complaints')
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode != 200) {
      throw ApiException(_extractError(response, 'Failed to load complaints'));
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((e) => Complaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Complaint> getComplaint(String token, String id) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/complaints/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw ApiException(_extractError(response, 'Failed to load complaint'));
    }
    return Complaint.fromJson(jsonDecode(response.body));
  }

  Future<Map<String, dynamic>> getDashboardStats(String token) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/complaints/stats/dashboard'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw ApiException(_extractError(response, 'Failed to load dashboard'));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

// ============================================================================
// AUTH PROVIDER (state)
// ============================================================================

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus status = AuthStatus.unknown;
  String? token;
  AppUser? currentUser;
  String? errorMessage;
  bool isLoading = false;

  Future<void> tryAutoLogin() async {
    final savedToken = await _authService.getSavedToken();
    if (savedToken == null) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      final user = await _authService.fetchCurrentUser(savedToken);
      token = savedToken;
      currentUser = user;
      status = AuthStatus.authenticated;
    } catch (_) {
      await _authService.clearToken();
      status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final newToken = await _authService.login(email, password);
      final user = await _authService.fetchCurrentUser(newToken);
      token = newToken;
      currentUser = user;
      status = AuthStatus.authenticated;
      return true;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('ApiException: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    String? phone,
    required String password,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _authService.register(name: name, email: email, phone: phone, password: password);
      return true;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('ApiException: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _authService.clearToken();
    token = null;
    currentUser = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    if (token == null) return;
    currentUser = await _authService.fetchCurrentUser(token!);
    notifyListeners();
  }
}

// ============================================================================
// COMPLAINT PROVIDER (state)
// ============================================================================

class ComplaintProvider extends ChangeNotifier {
  final ComplaintService _service = ComplaintService();

  List<Complaint> complaints = [];
  Map<String, dynamic>? dashboardStats;
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadComplaints(String token, {bool mineOnly = false, String? category}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      complaints = await _service.listComplaints(token: token, mineOnly: mineOnly, category: category);
    } catch (e) {
      errorMessage = e.toString().replaceFirst('ApiException: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDashboardStats(String token) async {
    try {
      dashboardStats = await _service.getDashboardStats(token);
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString().replaceFirst('ApiException: ', '');
    }
  }

  Future<Complaint?> submitComplaint({
    required String token,
    required String title,
    required String description,
    required String category,
    required String severity,
    required double latitude,
    required double longitude,
    String? address,
    String? landmark,
    bool isAnonymous = false,
    String? contactNumber,
    List<File> images = const [],
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final complaint = await _service.createComplaint(
        token: token,
        title: title,
        description: description,
        category: category,
        severity: severity,
        latitude: latitude,
        longitude: longitude,
        address: address,
        landmark: landmark,
        isAnonymous: isAnonymous,
        contactNumber: contactNumber,
        images: images,
      );
      complaints.insert(0, complaint);
      return complaint;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('ApiException: ', '');
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
