import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'receipt_ocr_service.dart';

class FinanceService {
  static const String _backendUrl = 'http://192.168.254.118:8000';

  // Default budget limits
  static const Map<String, double> defaultBudgets = {
    'Food': 5000.0,
    'Transport': 2000.0,
    'Bills': 10000.0,
    'Shopping': 3000.0,
    'Others': 5000.0,
  };

  /// Load the user's budget limits from SharedPreferences
  static Future<Map<String, double>> getBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, double> budgets = {};
    for (var category in defaultBudgets.keys) {
      budgets[category] = prefs.getDouble('budget_limit_$category') ?? defaultBudgets[category]!;
    }
    return budgets;
  }

  /// Save a new budget limit for a category in SharedPreferences
  static Future<void> setBudgetLimit(String category, double limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('budget_limit_$category', limit);
  }

  /// Calculates the number of days left in the current month (inclusive of today)
  static int getDaysLeftInMonth() {
    final now = DateTime.now();
    // Next month's 0th day is this month's last day
    final totalDays = DateTime(now.year, now.month + 1, 0).day;
    return totalDays - now.day + 1;
  }

  /// Helper to calculate safe to spend daily based on monthly limits, expenses, and actual income.
  static double calculateSafeToSpendDaily(double totalSpent, double totalIncome, Map<String, double> budgets) {
    double totalBudget = budgets.values.fold(0.0, (sum, val) => sum + val);
    double remainingBudget = totalBudget - totalSpent;
    double actualBalance = totalIncome - totalSpent;
    
    // You can't safely spend more than your actual balance, even if your budget allows it.
    double remainingToSpend = remainingBudget < actualBalance ? remainingBudget : actualBalance;
    
    int daysLeft = getDaysLeftInMonth();
    return remainingToSpend > 0 ? (remainingToSpend / daysLeft) : 0.0;
  }

  /// Generates a personalized financial insight from Gemini based on transaction logs.
  /// Uses a smart rule-based fallback if the API call fails or the key is empty.
  static Future<String> generateAiInsight({
    required List<Map<String, dynamic>> transactions,
    required Map<String, double> categoryTotals,
    required double totalIncome,
    required double totalExpense,
    String period = 'This Month',
  }) async {
    if (transactions.isEmpty) {
      return "You haven't recorded any transactions for $period yet. Tap the '+' button to get started!";
    }

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        return _generateLocalFallbackInsight(categoryTotals, totalIncome, totalExpense, period);
      }

      final recentTransactions = transactions.take(5).map((t) => {
        'title': t['title'],
        'amount': t['amount'],
        'category': t['category'],
        'type': t['type'],
      }).toList();

      final response = await http.post(
        Uri.parse('$_backendUrl/generate-insight'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: jsonEncode({
          'period': period,
          'total_income': totalIncome,
          'total_expense': totalExpense,
          'category_totals': categoryTotals,
          'recent_transactions': recentTransactions,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final resultText = data['insight'] as String?;
        if (resultText != null && resultText.isNotEmpty) {
          return resultText.trim();
        }
      } else {
        debugPrint("Generate Insight backend error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Generate Insight API Error: $e");
    }

    // Fall back to rule-based insight engine if API fails
    return _generateLocalFallbackInsight(categoryTotals, totalIncome, totalExpense, period);
  }

  static String _generateLocalFallbackInsight(
    Map<String, double> categoryTotals,
    double totalIncome,
    double totalExpense,
    String period,
  ) {
    // 1. Check if total expense exceeds total income
    if (totalExpense > totalIncome && totalIncome > 0) {
      return "⚠️ Warning: Your expenses exceed your income for $period. Try cutting down on non-essential spending.";
    }

    // 2. Find the highest spending category
    String highestCategory = 'Others';
    double highestAmount = 0.0;
    categoryTotals.forEach((category, amount) {
      if (amount > highestAmount) {
        highestAmount = amount;
        highestCategory = category;
      }
    });

    if (highestAmount > 0) {
      final r = DateTime.now().millisecondsSinceEpoch % 3; // Pseudo-random selector

      if (highestCategory == 'Food') {
        final list = [
          "💡 Food is your largest expense. Planning meals and eating in can help you save significantly this week.",
          "💡 You've spent ₱${highestAmount.toStringAsFixed(0)} on Food! Consider meal prepping tomorrow.",
          "💡 Did you know cooking at home saves an average of 40% per meal? Keep an eye on dining out!",
        ];
        return list[r];
      } else if (highestCategory == 'Transport') {
        final list = [
          "💡 You've spent ₱${highestAmount.toStringAsFixed(0)} on Transport. Consider walking or scheduling trips together.",
          "💡 Transport is eating up your budget. Maybe try carpooling or public transit if possible?",
          "💡 Those ride-shares add up quickly! Try limiting them to absolute necessities this week.",
        ];
        return list[r];
      } else if (highestCategory == 'Bills') {
        final list = [
          "💡 Fixed bills make up a large portion of your expenses. Make sure to review subscription services.",
          "💡 You've hit ₱${highestAmount.toStringAsFixed(0)} in Bills. Can you downgrade any recurring subscriptions?",
          "💡 Bills are unavoidable, but ensuring you aren't paying for unused services is an easy win!",
        ];
        return list[r];
      } else if (highestCategory == 'Shopping') {
        final list = [
          "💡 Shopping expenses are high this period. Try setting a 48-hour cool-off rule before buying non-essentials.",
          "💡 That ₱${highestAmount.toStringAsFixed(0)} in Shopping could have gone to savings! Ask yourself 'Do I need it?'",
          "💡 Retail therapy is nice, but reaching your savings goal feels even better. Watch out for impulse buys!",
        ];
        return list[r];
      } else {
        return "💡 Dynamic Insight: Your largest spending category is $highestCategory (₱${highestAmount.toStringAsFixed(0)}). Keep monitoring this area.";
      }
    }

    return "📊 Great start! Continue tracking your income and expenses to let our AI identify patterns and saving opportunities.";
  }

  // --- AI Endpoints ---

  /// Scans a receipt image using on-device ML Kit OCR.
  /// No API calls — runs entirely on the user's phone.
  static Future<Map<String, dynamic>?> scanReceipt(File image) async {
    try {
      return await ReceiptOcrService.scanReceipt(image);
    } catch (e) {
      debugPrint('Error scanning receipt: $e');
    }
    return null;
  }


  static Future<bool> addTransaction(Map<String, dynamic> data) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return false;

      final response = await http.post(
        Uri.parse('$_backendUrl/add-transaction'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
        body: jsonEncode(data),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error adding transaction: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> suggestGoalPlan(double targetAmount, int months) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return null;

      final response = await http.post(
        Uri.parse('$_backendUrl/suggest-goal-plan'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
        body: jsonEncode({
          'user_id': session.user.id,
          'target_amount': targetAmount,
          'deadline_months': months,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Error suggesting goal plan: $e');
    }
    return null;
  }
}
