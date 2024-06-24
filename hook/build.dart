import 'package:logging/logging.dart';
import 'package:native_assets_cli/native_assets_cli.dart';

const packageName = 'test_native_assets';

void main(List<String> args) async {
  await build(args, (config, output) async {
    final logger = Logger('');
    logger.log(Level.ALL, 'TEST!!! Building package ${config.packageName}');
  });
}
