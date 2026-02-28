import 'package:in_app_purchase/in_app_purchase.dart';

/// Stub purchase layer for post-approval Play Store rollout.
class PurchaseService {
  /// Fetches product metadata from Play Store.
  Future<List<ProductDetails>> getProducts() async {
    return <ProductDetails>[];
  }

  /// Starts purchase flow for selected product.
  Future<void> purchaseSubscription(ProductDetails product) async {
    return;
  }

  /// Verifies purchase and updates Firestore subscription state.
  Future<void> verifyAndActivate(PurchaseDetails purchase) async {
    return;
  }
}
