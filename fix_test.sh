sed -i '' 's/"ValidPass123"/passwordCrypto.encryptPassword("ValidPass123")/g' packages/repub_server/test/security_test.dart
sed -i '' 's/"Short1"/passwordCrypto.encryptPassword("Short1")/g' packages/repub_server/test/security_test.dart
sed -i '' 's/"lowercase123"/passwordCrypto.encryptPassword("lowercase123")/g' packages/repub_server/test/security_test.dart
sed -i '' 's/"UPPERCASE123"/passwordCrypto.encryptPassword("UPPERCASE123")/g' packages/repub_server/test/security_test.dart
sed -i '' 's/"NoNumbersHere"/passwordCrypto.encryptPassword("NoNumbersHere")/g' packages/repub_server/test/security_test.dart
sed -i '' 's/"AnotherPass123"/passwordCrypto.encryptPassword("AnotherPass123")/g' packages/repub_server/test/security_test.dart
