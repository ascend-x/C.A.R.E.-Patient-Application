import 'package:web3dart/crypto.dart';
import 'package:convert/convert.dart';
import 'dart:convert';

void main() {
  final sig = 'getRecords(address)';
  final hash = hex.encode(keccak256(utf8.encode(sig)));
  print('Function selector: 0x\${hash.substring(0, 8)}');
}
