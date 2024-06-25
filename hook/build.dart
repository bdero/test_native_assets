import 'dart:convert' as convert;
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_assets_cli/native_assets_cli.dart';

const packageName = 'test_native_assets';

final _logger = Logger('');

const _macosHostArtifacts = 'darwin-x64';
const _linuxHostArtifacts = 'linux-x64';
const _windowsHostArtifacts = 'windows-x64';

const _impellercLocations = [
  '$_macosHostArtifacts/impellerc',
  '$_linuxHostArtifacts/impellerc',
  '$_windowsHostArtifacts/impellerc.exe',
];

/// Locate the engine artifacts cache directory in the Flutter SDK.
Uri findEngineArtifactsDir() {
  // e.g.: `/path/to/flutter/bin/cache/dart-sdk/bin/dart`.
  final dartExec = Uri.file(Platform.resolvedExecutable);
  _logger.info('Dart executable: `${dartExec.toFilePath()}`');

  // e.g.: `/path/to/flutter/bin/cache/`.
  final engineArtifactsDir = dartExec.resolve(
      '../../artifacts/engine/'); // Note: The final slash is important.
  _logger.info(
      'Flutter SDK cache directory: `${engineArtifactsDir.toFilePath()}`');

  return engineArtifactsDir;
}

/// Locate the ImpellerC offline shader compiler in the engine artifacts cach
/// directory.
Future<Uri> findImpellerC() async {
  /////////////////////////////////////////////////////////////////////////////
  /// 1. If the `IMPELLERC` environment variable is set, use it.
  ///

  const impellercEnvVar = String.fromEnvironment('IMPELLERC', defaultValue: '');
  if (impellercEnvVar != '') {
    _logger.info('IMPELLERC environment variable: `$impellercEnvVar`');
    if (!await File(impellercEnvVar).exists()) {
      throw Exception(
          'IMPELLERC environment variable is set, but it doesn\'t point to a valid file!');
    }
    return Uri.file(impellercEnvVar);
  }

  /////////////////////////////////////////////////////////////////////////////
  /// 3. Search for the `impellerc` binary within the host-specific artifacts.
  ///

  Uri engineArtifactsDir = findEngineArtifactsDir();

  // No need to get fancy. Just search all the possible directories rather than
  // picking the correct one for the specific host type.
  Uri? found;
  List<Uri> tried = [];
  _logger.info('Searching for impellerc in artifacts directories...');
  for (final variant in _impellercLocations) {
    _logger.info('  Checking `$variant`...');
    final impellercPath = engineArtifactsDir.resolve(variant);
    if (await File(impellercPath.toFilePath()).exists()) {
      found = impellercPath;
      break;
    }
    tried.add(impellercPath);
  }
  if (found == null) {
    throw Exception(
        'Unable to find impellerc! Tried the following locations: $tried');
  }

  return found;
}

/// Loads a shader bundle manifest file and builds a shader bundle.
Future<void> _buildShaderBundle({
  required Uri inputManifestFilePath,
  required Uri outputBundleFilePath,
}) async {
  /////////////////////////////////////////////////////////////////////////////
  /// 1. Parse the manifest file.
  ///

  final manifest =
      await File(inputManifestFilePath.toFilePath()).readAsString();
  final decodedManifest = convert.json.decode(manifest);
  String reconstitutedManifest = convert.json.encode(decodedManifest);

  //throw Exception(reconstitutedManifest);

  /////////////////////////////////////////////////////////////////////////////
  /// 2. Build the shader bundle.
  ///

  final impellercExec = await findImpellerC();
  final shaderLibPath = impellercExec.resolve('./shader_lib');
  final impellercArgs = [
    '--sl=${outputBundleFilePath.toFilePath()}',
    '--shader-bundle=$reconstitutedManifest',
    '--include=${inputManifestFilePath.resolve('./').toFilePath()}',
    '--include=${shaderLibPath.toFilePath()}',
  ];

  final impellerc = Process.runSync(impellercExec.toFilePath(), impellercArgs);
  if (impellerc.exitCode != 0) {
    throw Exception(
        'Failed to build shader bundle: ${impellerc.stderr}\n${impellerc.stdout}');
  }
}

Future<void> buildShaderBundle(
    {required BuildConfig buildConfig,
    required BuildOutput buildOutput,
    required String manifestFileName}) async {
  String outputFileName = manifestFileName;
  if (outputFileName.endsWith('.json')) {
    outputFileName = outputFileName.substring(0, outputFileName.length - 5);
  }

  // TODO(bdero): Register DataAssets instead of outputting to the project directory once it's possible to do so.
  //final outDir = config.outputDirectory;
  final outDir = Directory.fromUri(
      buildConfig.packageRoot.resolve('build/shaderbundles/'));
  await outDir.create(recursive: true);
  final packageRoot = buildConfig.packageRoot;

  final inFile = packageRoot.resolve(manifestFileName);
  final outFile = outDir.uri.resolve(outputFileName);

  await _buildShaderBundle(
      inputManifestFilePath: inFile, outputBundleFilePath: outFile);
}

void main(List<String> args) async {
  await build(args, (config, output) async {
    await buildShaderBundle(
        buildConfig: config,
        buildOutput: output,
        manifestFileName: 'mybundle.shaderbundle.json');
  });
}
