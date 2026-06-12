import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'finance_service.dart';

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  bool _isLoading = true;
  double _safeToSpendDaily = 0.0;
  int _daysLeft = 0;

  Map<String, double> _budgets = FinanceService.defaultBudgets;
  Map<String, double> _categorySpent = {
    'Food': 0.0,
    'Transport': 0.0,
    'Bills': 0.0,
    'Shopping': 0.0,
    'Others': 0.0,
  };

  final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  @override
  void initState() {
    super.initState();
    _fetchBudgetData();
  }

  Future<void> _fetchBudgetData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Load budget limits
      final loadedBudgets = await FinanceService.getBudgets();

      // Load expenses from Supabase
      final data = await Supabase.instance.client
          .from('transactions')
          .select()
          .eq('user_id', userId);

      final now = DateTime.now();
      double spentSum = 0.0;
      double incomeSum = 0.0;
      final tempSpent = {
        'Food': 0.0,
        'Transport': 0.0,
        'Bills': 0.0,
        'Shopping': 0.0,
        'Others': 0.0,
      };

      for (var t in data) {
        final date = DateTime.parse(t['created_at']).toLocal();
        // Only count transactions within the current month & year
        if (date.year == now.year && date.month == now.month) {
          final amount = (t['amount'] as num).toDouble();
          
          if (t['type'] == 'expense') {
            final category = t['category'] as String? ?? 'Others';
            
            if (tempSpent.containsKey(category)) {
              tempSpent[category] = tempSpent[category]! + amount;
            } else {
              tempSpent['Others'] = tempSpent['Others']! + amount;
            }
            spentSum += amount;
          } else if (t['type'] == 'income') {
            incomeSum += amount;
          }
        }
      }

      int daysRemaining = FinanceService.getDaysLeftInMonth();
      double safeDaily = FinanceService.calculateSafeToSpendDaily(spentSum, incomeSum, loadedBudgets);

      if (mounted) {
        setState(() {
          _budgets = loadedBudgets;
          _categorySpent = tempSpent;
          _daysLeft = daysRemaining;
          _safeToSpendDaily = safeDaily;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading budget page data: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEditBudgetSheet({String? initialCategory}) {
    String selectedCategory = initialCategory ?? _budgets.keys.first;
    final limitController = TextEditingController(
      text: _budgets[selectedCategory]?.toStringAsFixed(0) ?? '5000',
    );
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Configure Budget Limits',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Category Selector
                      const Text(
                        'Category',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: _budgets.keys.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(cat),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedCategory = val;
                              limitController.text = (_budgets[selectedCategory] ?? 5000).toStringAsFixed(0);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 20),

                      // Limit Input
                      const Text(
                        'Monthly Budget Limit (₱)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: limitController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        decoration: InputDecoration(
                          hintText: 'Enter monthly amount',
                          prefixText: '₱ ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Please enter a limit';
                          final numVal = double.tryParse(val.trim());
                          if (numVal == null || numVal < 0) return 'Please enter a valid positive number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (formKey.currentState!.validate()) {
                                    setModalState(() => isSaving = true);
                                    
                                    final newLimit = double.parse(limitController.text.trim());
                                    await FinanceService.setBudgetLimit(selectedCategory, newLimit);
                                    
                                    if (mounted) {
                                      Navigator.pop(context);
                                      setState(() => _isLoading = true);
                                      _fetchBudgetData();
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF634DFF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isSaving
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  'Save Budget Limit',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Budgets',
          style: TextStyle(
            color: Color(0xFF634DFF),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF634DFF)))
          : RefreshIndicator(
              onRefresh: _fetchBudgetData,
              color: const Color(0xFF634DFF),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Safe to spend card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2E62FF), Color(0xFF634DFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2E62FF).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Safe to Spend Daily',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _currencyFormat.format(_safeToSpendDaily),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_daysLeft Days left in this month',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Category Limits',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showEditBudgetSheet(),
                          icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF634DFF)),
                          label: const Text(
                            'Edit',
                            style: TextStyle(color: Color(0xFF634DFF), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Dynamic Budget Progress Items
                    ..._budgets.entries.map((entry) {
                      final category = entry.key;
                      final budgetLimit = entry.value;
                      final spent = _categorySpent[category] ?? 0.0;
                      final isOverBudget = spent > budgetLimit;
                      final double percent = budgetLimit > 0 ? (spent / budgetLimit) : 0.0;

                      Color categoryColor;
                      switch (category) {
                        case 'Food':
                          categoryColor = const Color(0xFF8C3CFF);
                          break;
                        case 'Transport':
                          categoryColor = const Color(0xFF2E62FF);
                          break;
                        case 'Bills':
                          categoryColor = const Color(0xFF00BCC9);
                          break;
                        case 'Shopping':
                          categoryColor = const Color(0xFF00C853);
                          break;
                        default:
                          categoryColor = const Color(0xFFFFB300);
                      }

                      return InkWell(
                        onTap: () => _showEditBudgetSheet(initialCategory: category),
                        borderRadius: BorderRadius.circular(16),
                        child: _buildBudgetCard(
                          category,
                          _currencyFormat.format(spent),
                          _currencyFormat.format(budgetLimit),
                          percent,
                          categoryColor,
                          isAlert: isOverBudget,
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBudgetCard(
    String title,
    String spent,
    String total,
    double percent,
    Color color, {
    required bool isAlert,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isAlert ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAlert ? Colors.red.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$spent / $total',
                style: TextStyle(
                  color: isAlert ? Colors.red : Colors.black87,
                  fontWeight: isAlert ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent > 1.0 ? 1.0 : percent,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                isAlert ? Colors.red : color,
              ),
              minHeight: 10,
            ),
          ),
          if (isAlert) ...[
            const SizedBox(height: 8),
            const Text(
              '⚠️ You have exceeded this budget limit.',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
