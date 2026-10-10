import '../domain/membership_features.dart';

typedef FeatureRpc = Future<dynamic> Function(String name);

class MembershipFeaturesRepository {
  MembershipFeaturesRepository({required FeatureRpc rpc}) : _rpc = rpc;
  final FeatureRpc _rpc;
  Future<MembershipFeatures> load() async {
    final result = await _rpc('get_my_membership_features');
    return MembershipFeatures.fromJson(
        Map<String, dynamic>.from(result as Map));
  }
}
