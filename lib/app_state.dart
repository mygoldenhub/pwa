import 'package:flutter/foundation.dart';
import 'package:pwa/services/auth_service.dart';
import 'package:pwa/services/product_service.dart';

class AppState extends ChangeNotifier {
  final AuthService auth;
  final ProductService products;

  AppState({required this.auth, required this.products}) {
    auth.addListener(_bubble);
    products.addListener(_bubble);
  }

  bool get isReady => auth.isInitialized && products.isInitialized;

  Future<void> init() async {
    await Future.wait([
      auth.init(),
      products.init(),
    ]);
    notifyListeners();
  }

  void _bubble() => notifyListeners();

  @override
  void dispose() {
    auth.removeListener(_bubble);
    products.removeListener(_bubble);
    super.dispose();
  }
}
