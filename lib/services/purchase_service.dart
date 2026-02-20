import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Stub purchase layer for post-approval Play Store rollout.
class PurchaseService {
  /// Fetches product metadata from Play Store.
  ///
  /// TODO: implement after Play Store approval.
  Future<List<ProductDetails>> getProducts() async {
    debugPrint('PurchaseService.getProducts() - stub, not yet implemented');
    return <ProductDetails>[];
  }

  /// Starts purchase flow for selected product.
  ///
  /// TODO: implement after Play Store approval.
  Future<void> purchaseSubscription(ProductDetails product) async {
    debugPrint(
      'PurchaseService.purchaseSubscription() - stub for ${product.id}',
    );
  }

  /// Verifies purchase and updates Firestore subscription state.
  ///
  /// TODO: implement after Play Store approval.
  Future<void> verifyAndActivate(PurchaseDetails purchase) async {
    debugPrint(
      'PurchaseService.verifyAndActivate() - stub for ${purchase.productID}',
    );
  }
}
