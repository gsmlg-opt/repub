import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

/// Result of validating and parsing a package tarball.
sealed class PublishResult {}

class PublishSuccess extends PublishResult {
  final String packageName;
  final String version;
  final Map<String, dynamic> pubspec;
  final String sha256Hash;
  final Uint8List tarballBytes;

  PublishSuccess({
    required this.packageName,
    required this.version,
    required this.pubspec,
    required this.sha256Hash,
    required this.tarballBytes,
  });
}

class PublishError extends PublishResult {
  final String message;
  PublishError(this.message);
}

/// Validate and parse a package tarball.
Future<PublishResult> validateTarball(Uint8List tarballBytes) async {
  try {
    // Calculate SHA256
    final sha256Hash = sha256.convert(tarballBytes).toString();

    // Decode the tarball
    final gzipDecoded = GZipDecoder().decodeBytes(tarballBytes);
    final archive = TarDecoder().decodeBytes(gzipDecoded);

    // Find pubspec.yaml
    ArchiveFile? pubspecFile;
    for (final file in archive) {
      // pubspec.yaml can be at root or in a subdirectory
      if (file.name == 'pubspec.yaml' || file.name.endsWith('/pubspec.yaml')) {
        // Prefer the one at root or shallowest level
        if (pubspecFile == null ||
            file.name.split('/').length < pubspecFile.name.split('/').length) {
          pubspecFile = file;
        }
      }
    }

    if (pubspecFile == null) {
      return PublishError('No pubspec.yaml found in archive');
    }

    // Parse pubspec.yaml
    final pubspecContent = utf8.decode(pubspecFile.content as List<int>);
    final pubspecYaml = loadYaml(pubspecContent);

    if (pubspecYaml is! YamlMap) {
      return PublishError('Invalid pubspec.yaml: not a map');
    }

    final pubspec = _convertYamlToJson(pubspecYaml);

    // Validate required fields
    final name = pubspec['name'];
    if (name is! String || name.isEmpty) {
      return PublishError('pubspec.yaml missing or invalid "name" field');
    }

    final version = pubspec['version'];
    if (version is! String || version.isEmpty) {
      return PublishError('pubspec.yaml missing or invalid "version" field');
    }

    // Validate package name format
    if (!_isValidPackageName(name)) {
      return PublishError(
        'Invalid package name "$name". '
        'Package names must be lowercase with underscores, '
        'starting with a letter.',
      );
    }

    // Validate version format (basic semver check)
    if (!_isValidVersion(version)) {
      return PublishError(
        'Invalid version "$version". '
        'Version must be a valid semantic version.',
      );
    }

    return PublishSuccess(
      packageName: name,
      version: version,
      pubspec: pubspec,
      sha256Hash: sha256Hash,
      tarballBytes: tarballBytes,
    );
  } on ArchiveException catch (e) {
    return PublishError('Invalid archive: ${e.message}');
  } on FormatException catch (e) {
    return PublishError('Invalid pubspec.yaml format: ${e.message}');
  } catch (e) {
    return PublishError('Failed to process archive: $e');
  }
}

/// Convert YAML map to JSON-compatible map.
Map<String, dynamic> _convertYamlToJson(YamlMap yaml) {
  return yaml.map((key, value) {
    final jsonValue = _convertValue(value);
    return MapEntry(key.toString(), jsonValue);
  });
}

dynamic _convertValue(dynamic value) {
  if (value is YamlMap) {
    return _convertYamlToJson(value);
  } else if (value is YamlList) {
    return value.map(_convertValue).toList();
  } else {
    return value;
  }
}

/// Check if a package name is valid.
bool _isValidPackageName(String name) {
  // Package names should be lowercase, with underscores allowed
  // Must start with a letter
  return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name);
}

/// Check if a version string is valid (basic semver).
bool _isValidVersion(String version) {
  // Basic semver: x.y.z with optional prerelease and build
  return RegExp(
    r'^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$',
  ).hasMatch(version);
}
