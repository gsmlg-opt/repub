import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

import '../services/api_client.dart';

/// Version display component that fetches and displays version info
@client
class VersionDisplay extends StatefulComponent {
  const VersionDisplay({super.key});

  @override
  State<VersionDisplay> createState() => _VersionDisplayState();
}

class _VersionDisplayState extends State<VersionDisplay> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final client = ApiClient();
    try {
      final versionInfo = await client.getVersion();
      setState(() {
        _version = versionInfo['version'] as String?;
      });
    } catch (_) {
      // Ignore version fetch errors
    } finally {
      client.dispose();
    }
  }

  @override
  Component build(BuildContext context) {
    if (_version == null || _version == 'unknown') {
      return span([]);
    }
    return span([Component.text(' v$_version')]);
  }
}
