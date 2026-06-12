import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'finance_service.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String _selectedPeriod = 'This Month';
  bool _isLoading = true;
  bool _isAiLoading = true;
  double _totalSpent = 0.0;
  String _aiInsight = "Analyzing your spending patterns...";

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];

  Map<String, double> _categoryTotals = {
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
    _fetchAnalyticsData();
  }

  Future<void> _fetchAnalyticsData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _transactions = List<Map<String, dynamic>>.from(data);
          _filterTransactions();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching analytics: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterTransactions() {
    final now = DateTime.now();
    _filteredTransactions = [];
    _categoryTotals = {
      'Food': 0.0,
      'Transport': 0.0,
      'Bills': 0.0,
      'Shopping': 0.0,
      'Others': 0.0,
    };
    _totalSpent = 0.0;

    for (var t in _transactions) {
      if (t['type'] == 'expense') {
        final date = DateTime.parse(t['created_at']).toLocal();
        bool matchesPeriod = false;

        if (_selectedPeriod == 'This Week') {
          // Last 7 days
          final startOfWeek = now.subtract(const Duration(days: 7));
          matchesPeriod = date.isAfter(startOfWeek);
        } else if (_selectedPeriod == 'This Month') {
          // Current calendar month
          matchesPeriod = (date.year == now.year && date.month == now.month);
        } else if (_selectedPeriod == 'This Year') {
          // Current calendar year
          matchesPeriod = (date.year == now.year);
        }

        if (matchesPeriod) {
          _filteredTransactions.add(t);
          final amount = (t['amount'] as num).toDouble();
          final category = t['category'] as String? ?? 'Others';

          if (_categoryTotals.containsKey(category)) {
            _categoryTotals[category] = _categoryTotals[category]! + amount;
          } else {
            _categoryTotals['Others'] = _categoryTotals['Others']! + amount;
          }
          _totalSpent += amount;
        }
      }
    }

    // Run AI Insight generation asynchronously for the new filter
    _generatePeriodInsight();
  }

  Future<void> _generatePeriodInsight() async {
    if (mounted) {
      setState(() => _isAiLoading = true);
    }

    // Calculate dynamic incomes for reference in AI summaries
    double incomeSum = 0.0;
    final now = DateTime.now();
    for (var t in _transactions) {
      if (t['type'] == 'income') {
        final date = DateTime.parse(t['created_at']).toLocal();
        bool matches = false;
        if (_selectedPeriod == 'This Week') {
          matches = date.isAfter(now.subtract(const Duration(days: 7)));
        } else if (_selectedPeriod == 'This Month') {
          matches = (date.year == now.year && date.month == now.month);
        } else if (_selectedPeriod == 'This Year') {
          matches = (date.year == now.year);
        }
        if (matches) {
          incomeSum += (t['amount'] as num).toDouble();
        }
      }
    }

    final insight = await FinanceService.generateAiInsight(
      transactions: _filteredTransactions,
      categoryTotals: _categoryTotals,
      totalIncome: incomeSum,
      totalExpense: _totalSpent,
      period: _selectedPeriod,
    );

    if (mounted) {
      setState(() {
        _aiInsight = insight;
        _isAiLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Analytics',
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
              onRefresh: _fetchAnalyticsData,
              color: const Color(0xFF634DFF),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period Selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedPeriod,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down),
                          items: ['This Week', 'This Month', 'This Year'].map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                value,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedPeriod = newValue;
                                _filterTransactions();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Total Spent Summary
                    Text(
                      'Total Spent ($_selectedPeriod)',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currencyFormat.format(_totalSpent),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),

                    // AI Insight Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF634DFF).withOpacity(0.08),
                            const Color(0xFF8C3CFF).withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF634DFF).withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Color(0xFF634DFF),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _isAiLoading
                                ? Row(
                                    children: [
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF634DFF)),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Gemini is drafting recommendations...',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    _aiInsight,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                      height: 1.4,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Automated Categories Breakdown
                    const Text(
                      'AI Categorized Spending',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    if (_filteredTransactions.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            "No expense transactions found for this period.",
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ),
                      )
                    else
                      ..._categoryTotals.entries.map((entry) {
                        final category = entry.key;
                        final amount = entry.value;
                        final double percent = _totalSpent > 0 ? (amount / _totalSpent) : 0.0;

                        if (amount == 0.0) return const SizedBox.shrink();

                        Color categoryColor;
                        String displayTitle = category;
                        switch (category) {
                          case 'Food':
                            categoryColor = const Color(0xFF8C3CFF);
                            displayTitle = 'Food & Dining';
                            break;
                          case 'Transport':
                            categoryColor = const Color(0xFF2E62FF);
                            break;
                          case 'Bills':
                            categoryColor = const Color(0xFF00BCC9);
                            displayTitle = 'Bills & Utilities';
                            break;
                          case 'Shopping':
                            categoryColor = const Color(0xFF00C853);
                            break;
                          default:
                            categoryColor = const Color(0xFFFFB300);
                        }

                        return _buildCategoryStat(
                          displayTitle,
                          _currencyFormat.format(amount),
                          percent,
                          categoryColor,
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCategoryStat(
    String title,
    String amount,
    double percent,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Row(
                children: [
                  Text(amount, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text(
                    '(${(percent * 100).toStringAsFixed(0)}%)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.grey.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}
