import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';

/// On-device receipt OCR service using Google ML Kit.
/// Zero API calls — runs entirely on the user's phone.
class ReceiptOcrService {
  static final TextRecognizer _textRecognizer = TextRecognizer();

  /// Scans a receipt image and extracts structured transaction data.
  /// Returns a map with keys: merchant, amount, date, category (all nullable).
  static Future<Map<String, dynamic>?> scanReceipt(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final rawText = recognizedText.text;
      if (rawText.trim().isEmpty) return null;

      debugPrint('--- ML Kit OCR Raw Text ---');
      debugPrint(rawText);
      debugPrint('--- End OCR ---');

      final textLines = recognizedText.blocks
          .expand((block) => block.lines)
          .where((line) => line.text.trim().isNotEmpty)
          .toList();

      final stringLines = textLines.map((l) => l.text.trim()).toList();

      final merchant = _extractMerchant(textLines);
      final amount = _extractAmount(stringLines);
      final date = _extractDate(stringLines);
      final category = _categorizeFromMerchant(merchant ?? '');

      return {
        'merchant': merchant,
        'amount': amount,
        'date': date,
        'category': category,
      };
    } catch (e) {
      debugPrint('ReceiptOcrService error: $e');
      return null;
    }
  }

  /// Extracts the merchant name — typically the first prominent text line
  /// that isn't a date, number, or generic receipt label.
  static String? _extractMerchant(List<TextLine> lines) {
    final skipPatterns = RegExp(
      r'^(receipt|official|invoice|vat|tin|reg|pos|terminal|cashier|date|time|tel|phone|fax|address|#|no\.|or no|si no|transaction|ref|thank|welcome|--|cash|change)'
      , caseSensitive: false,
    );
    final containsSkip = RegExp(
      r'(vat reg|tin:|tin #|tin no|machine no|serial no|permit no|ptr no|epn|min:|sn:|accrd|accreditation|operated by|franchisee|this serves as|total due|amount due|change due|cash tendered|sales invoice|order no|table no)',
      caseSensitive: false,
    );
    // Ignore common address strings if they have numbers
    final addressPattern = RegExp(r'\d+.*(st\.|street|ave|avenue|blvd|boulevard|road|rd\.)', caseSensitive: false);
    final pureNumberPattern = RegExp(r'^[\d\s.,₱PHP%\-:\/]+$');

    List<TextLine> candidates = [];
    
    // Check the first 15 lines for candidates
    for (int i = 0; i < lines.length && i < 15; i++) {
      final text = lines[i].text.trim();
      if (text.length < 3) continue;
      if (pureNumberPattern.hasMatch(text)) continue;
      if (skipPatterns.hasMatch(text)) continue;
      if (containsSkip.hasMatch(text)) continue;
      if (addressPattern.hasMatch(text)) continue;
      
      candidates.add(lines[i]);
    }

    if (candidates.isEmpty) {
      for (final line in lines) {
        final text = line.text.trim();
        if (text.length > 2 && !pureNumberPattern.hasMatch(text)) {
          return text;
        }
      }
      return null;
    }

    double maxHeight = 0;
    for (var c in candidates) {
      if (c.boundingBox.height > maxHeight) {
        maxHeight = c.boundingBox.height;
      }
    }

    for (var c in candidates) {
      // If it's reasonably close to the max height (at least 80% as tall), 
      // we pick the first one since merchants are usually at the very top.
      if (c.boundingBox.height >= maxHeight * 0.8) {
        return c.text.trim();
      }
    }
    
    return candidates.first.text.trim();
  }

  /// Extracts the total amount from the receipt.
  /// Prioritizes "TOTAL DUE" and Philippine peso sign patterns.
  static double? _extractAmount(List<String> lines) {
    // Step 1: Look for "TOTAL DUE" or similar keywords WITH an amount on the SAME line
    final sameLine = [
      // "TOTAL DUE ₱150.00" or "TOTAL DUE: 150.00" or "TOTAL DUE P 150.00"
      RegExp(r'total\s*due[:\s]*[₱Pp]?\s*([\d,]+\.?\d*)', caseSensitive: false),
      RegExp(r'grand\s*total[:\s]*[₱Pp]?\s*([\d,]+\.?\d*)', caseSensitive: false),
      RegExp(r'amount\s*due[:\s]*[₱Pp]?\s*([\d,]+\.?\d*)', caseSensitive: false),
      RegExp(r'total\s*(?:amount|sale|tendered)?[:\s]*[₱Pp]?\s*([\d,]+\.?\d*)', caseSensitive: false),
      RegExp(r'balance\s*due[:\s]*[₱Pp]?\s*([\d,]+\.?\d*)', caseSensitive: false),
    ];

    for (final pattern in sameLine) {
      for (int i = 0; i < lines.length; i++) {
        final match = pattern.firstMatch(lines[i]);
        if (match != null) {
          final parsed = _parseAmount(match.group(1));
          if (parsed != null && parsed > 0) {
            debugPrint('Amount matched on same line: "${lines[i]}" → $parsed');
            return parsed;
          }
          // Amount might be on the NEXT line (OCR sometimes splits lines)
          if (i + 1 < lines.length) {
            final nextLineParsed = _parseAmountFromLine(lines[i + 1]);
            if (nextLineParsed != null && nextLineParsed > 0) {
              debugPrint('Amount matched on next line: "${lines[i + 1]}" → $nextLineParsed');
              return nextLineParsed;
            }
          }
        }
      }
    }

    // Step 2: Look for lines that just have a keyword like "TOTAL DUE" without amount,
    // then check the next line for the amount
    final keywordOnly = RegExp(
      r'(total\s*due|grand\s*total|amount\s*due|balance\s*due|total)',
      caseSensitive: false,
    );
    for (int i = 0; i < lines.length; i++) {
      if (keywordOnly.hasMatch(lines[i])) {
        // Check next 1-2 lines for a standalone amount
        for (int j = 1; j <= 2 && (i + j) < lines.length; j++) {
          final nextAmount = _parseAmountFromLine(lines[i + j]);
          if (nextAmount != null && nextAmount > 0) {
            debugPrint('Amount found after keyword "${lines[i]}": "${lines[i + j]}" → $nextAmount');
            return nextAmount;
          }
        }
      }
    }

    // Step 3: Fallback — find the largest ₱/P amount on any line
    double largestAmount = 0;
    for (final line in lines) {
      final amounts = RegExp(r'[₱Pp]\s*([\d,]+\.?\d{0,2})').allMatches(line);
      for (final match in amounts) {
        final parsed = _parseAmount(match.group(1));
        if (parsed != null && parsed > largestAmount) {
          largestAmount = parsed;
        }
      }
    }

    return largestAmount > 0 ? largestAmount : null;
  }

  /// Parse amount string like "1,500.00" or "150" into double.
  static double? _parseAmount(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final cleaned = raw.replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  /// Try to extract a standalone amount from a line (e.g., "₱150.00" or "1,500.00").
  static double? _parseAmountFromLine(String line) {
    // Match "₱150.00", "P 1,500.00", "PHP 150.00", or just "150.00"
    final patterns = [
      RegExp(r'[₱Pp]\s*([\d,]+\.?\d*)'),
      RegExp(r'PHP\s*([\d,]+\.?\d*)', caseSensitive: false),
      RegExp(r'^[\s]*([\d,]+\.\d{2})[\s]*$'),  // standalone "150.00"
    ];
    for (final p in patterns) {
      final match = p.firstMatch(line);
      if (match != null) {
        return _parseAmount(match.group(1));
      }
    }
    return null;
  }

  /// Extracts a date from the receipt text.
  /// Handles common PH receipt formats.
  static String? _extractDate(List<String> lines) {
    final datePatterns = [
      // MM/DD/YYYY or MM-DD-YYYY
      RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})'),
      // YYYY-MM-DD (ISO)
      RegExp(r'(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})'),
      // DD MMM YYYY (e.g., 10 May 2024)
      RegExp(r'(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+(\d{4})', caseSensitive: false),
      // MMM DD, YYYY (e.g., May 10, 2024)
      RegExp(r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+(\d{1,2}),?\s+(\d{4})', caseSensitive: false),
    ];

    final monthMap = {
      'jan': '01', 'feb': '02', 'mar': '03', 'apr': '04',
      'may': '05', 'jun': '06', 'jul': '07', 'aug': '08',
      'sep': '09', 'oct': '10', 'nov': '11', 'dec': '12',
    };

    for (final line in lines) {
      // Pattern 1: MM/DD/YYYY
      var match = datePatterns[0].firstMatch(line);
      if (match != null) {
        final m = match.group(1)!.padLeft(2, '0');
        final d = match.group(2)!.padLeft(2, '0');
        final y = match.group(3)!;
        return '$y-$m-$d';
      }

      // Pattern 2: YYYY-MM-DD
      match = datePatterns[1].firstMatch(line);
      if (match != null) {
        final y = match.group(1)!;
        final m = match.group(2)!.padLeft(2, '0');
        final d = match.group(3)!.padLeft(2, '0');
        return '$y-$m-$d';
      }

      // Pattern 3: DD MMM YYYY
      match = datePatterns[2].firstMatch(line);
      if (match != null) {
        final d = match.group(1)!.padLeft(2, '0');
        final m = monthMap[match.group(2)!.substring(0, 3).toLowerCase()] ?? '01';
        final y = match.group(3)!;
        return '$y-$m-$d';
      }

      // Pattern 4: MMM DD, YYYY
      match = datePatterns[3].firstMatch(line);
      if (match != null) {
        final m = monthMap[match.group(1)!.substring(0, 3).toLowerCase()] ?? '01';
        final d = match.group(2)!.padLeft(2, '0');
        final y = match.group(3)!;
        return '$y-$m-$d';
      }
    }
    return null;
  }

  /// Categorizes the transaction based on the merchant name.
  /// Uses the same local rule-based logic as the auto-categorizer.
  static String _categorizeFromMerchant(String merchant) {
    final s = merchant.toLowerCase().trim();

    const food = [
      'jollibee', 'mcdo', "mcdonald", 'kfc', 'chowking', 'mang inasal',
      'greenwich', 'yellow cab', 'pizza hut', 'domino', 'starbucks',
      'coffee bean', 'dunkin', 'krispy kreme', 'red ribbon', 'goldilocks',
      "max's", 'pancake house', 'shakeys', 'army navy', 'burger king',
      'bonchon', 'potato corner', 'sbarro', 'jamba juice', 'happy lemon',
      '7-eleven', '7eleven', 'ministop', 'family mart', 'lawson',
      'grabfood', 'foodpanda', 'restaurant', 'eatery', 'cafe', 'bakery',
      'milk tea', 'grocery', 'supermarket', 'puregold', 'savemore',
      'walter mart', 'food', 'snack', 'meal', 'lunch', 'dinner', 'breakfast',
      'sm supermarket', 'robinsons supermarket', 'landers',
    ];

    const transport = [
      'angkas', 'joyride', 'grab', 'lalamove', 'maxim', 'indrive',
      'mrt', 'lrt', 'pnr', 'beep', 'bus', 'jeep', 'taxi',
      'petron', 'shell', 'caltex', 'seaoil', 'phoenix', 'gasoline',
      'toll', 'nlex', 'slex', 'parking', 'transport', 'fare',
    ];

    const bills = [
      'meralco', 'maynilad', 'manila water', 'pldt', 'globe', 'smart',
      'converge', 'sky', 'netflix', 'spotify', 'philhealth', 'sss',
      'pagibig', 'pag-ibig', 'rent', 'electric', 'internet', 'wifi',
      'subscription', 'insurance', 'premium', 'water bill',
    ];

    const shopping = [
      'shopee', 'lazada', 'zalora', 'shein', 'temu', 'amazon',
      'sm store', 'sm department', 'robinsons', 'landmark', 'rustan',
      'h&m', 'uniqlo', 'zara', 'nike', 'adidas', 'penshoppe', 'bench',
      'watsons', 'mercury drug', 'national bookstore',
      'abenson', 'gadget', 'phone', 'laptop', 'clothing', 'shoes',
    ];

    const entertainment = [
      'cinema', 'movie', 'concert', 'steam', 'playstation', 'xbox',
      'bowling', 'karaoke', 'arcade', 'gym', 'fitness', 'spa', 'salon',
      'resorts world', 'okada', 'solaire',
    ];

    for (final kw in food) { if (s.contains(kw)) return 'Food'; }
    for (final kw in transport) { if (s.contains(kw)) return 'Transport'; }
    for (final kw in bills) { if (s.contains(kw)) return 'Bills'; }
    for (final kw in shopping) { if (s.contains(kw)) return 'Shopping'; }
    for (final kw in entertainment) { if (s.contains(kw)) return 'Entertainment'; }

    return 'Shopping'; // sensible default for receipts
  }

  /// Clean up resources when no longer needed.
  static void dispose() {
    _textRecognizer.close();
  }
}
