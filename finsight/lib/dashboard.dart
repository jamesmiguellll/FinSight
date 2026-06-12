import 'package:flutter/material.dart';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'profile.dart';
import 'analytics.dart';
import 'budget.dart';
import 'add_transaction_bottom_sheet.dart';
import 'finance_service.dart';
import 'goals.dart';
import 'transactions_page.dart';

class HomePage extends StatefulWidget {
  final String userName;

  const HomePage({super.key, required this.userName});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  
  List<Map<String, dynamic>> _transactions = [];
  double _totalBalance = 0.0;
  double _totalIncome = 0.0;
  double _totalExpense = 0.0;
  bool _isLoading = true;

  Map<String, double> _categoryTotals = {
    'Food': 0.0,
    'Transport': 0.0,
    'Bills': 0.0,
    'Shopping': 0.0,
    'Others': 0.0,
  };

  Map<String, double> _budgets = FinanceService.defaultBudgets;
  String _aiInsight = "Loading your financial insights...";
  bool _isAiLoading = true;
  List<double> _weeklyHeights = List.filled(10, 15.0);

  final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final loadedBudgets = await FinanceService.getBudgets();

      final data = await Supabase.instance.client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _budgets = loadedBudgets;
          _transactions = List<Map<String, dynamic>>.from(data);
          _calculateTotals();
          _calculateWeeklyHeights();
          _isLoading = false;
        });

        // Trigger AI Insight in the background
        _generateAiInsight();
      }
    } catch (e) {
      debugPrint("Error fetching transactions: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _calculateWeeklyHeights() {
    final now = DateTime.now();
    final Map<String, double> dailySpends = {};

    // Pre-populate last 10 days
    for (int i = 0; i < 10; i++) {
      final dateStr = DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: i)));
      dailySpends[dateStr] = 0.0;
    }

    // Populate actual spending
    for (var t in _transactions) {
      if (t['type'] == 'expense') {
        final date = DateTime.parse(t['created_at']).toLocal();
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        if (dailySpends.containsKey(dateStr)) {
          dailySpends[dateStr] = dailySpends[dateStr]! + (t['amount'] as num).toDouble();
        }
      }
    }

    double maxSpend = dailySpends.values.fold(0.0, (max, val) => val > max ? val : max);

    final List<double> heights = [];
    for (int i = 9; i >= 0; i--) {
      final dateStr = DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: i)));
      final spend = dailySpends[dateStr] ?? 0.0;

      if (maxSpend == 0.0) {
        heights.add(15.0);
      } else {
        double height = 15.0 + (spend / maxSpend) * 45.0;
        heights.add(height);
      }
    }

    setState(() {
      _weeklyHeights = heights;
    });
  }

  Future<void> _generateAiInsight() async {
    if (mounted) {
      setState(() => _isAiLoading = true);
    }

    final insight = await FinanceService.generateAiInsight(
      transactions: _transactions,
      categoryTotals: _categoryTotals,
      totalIncome: _totalIncome,
      totalExpense: _totalExpense,
    );

    if (mounted) {
      setState(() {
        _aiInsight = insight;
        _isAiLoading = false;
      });
    }
  }

  void _calculateTotals() {
    _totalIncome = 0.0;
    _totalExpense = 0.0;
    _categoryTotals = {
      'Food': 0.0,
      'Transport': 0.0,
      'Bills': 0.0,
      'Shopping': 0.0,
      'Others': 0.0,
    };

    for (var t in _transactions) {
      final amount = (t['amount'] as num).toDouble();
      if (t['type'] == 'income') {
        _totalIncome += amount;
      } else {
        _totalExpense += amount;
        final cat = t['category'] as String? ?? 'Others';
        if (_categoryTotals.containsKey(cat)) {
          _categoryTotals[cat] = _categoryTotals[cat]! + amount;
        } else {
          _categoryTotals['Others'] = _categoryTotals['Others']! + amount;
        }
      }
    }
    _totalBalance = _totalIncome - _totalExpense;
  }

  Future<void> _deleteTransaction(String id) async {
    try {
      await Supabase.instance.client.from('transactions').delete().eq('id', id);
      _fetchTransactions();
    } catch (e) {
      debugPrint("Error deleting: $e");
    }
  }

  void _showAddTransactionModal({Map<String, dynamic>? transaction}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => AddTransactionBottomSheet(
        existingTransaction: transaction,
        onSaved: () {
          setState(() => _isLoading = true);
          _fetchTransactions();
        },
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildDashboardView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildSpendingInsights(),
          const SizedBox(height: 32),
          _buildRecentTransactions(),
          const SizedBox(height: 32),
          _buildBudgetProgress(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      _buildDashboardView(),
      const AnalyticsPage(),
      const BudgetPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTransactionModal,
        backgroundColor: const Color(0xFF634DFF),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        color: Colors.white,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_outlined, 'Home', 0),
              _buildNavItem(Icons.pie_chart_outline, 'Analytics', 1),
              const SizedBox(width: 48), // Space for FAB
              _buildNavItem(Icons.track_changes_outlined, 'Budget', 2),
              _buildNavItem(Icons.person_outline, 'Profile', 3),
            ],
          ),
        ),
      ),
      body: screens[_currentIndex],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E62FF), Color(0xFF8C3CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'FinSight',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const GoalsPage()),
                  );
                },
                child: CircleAvatar(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: const Icon(Icons.savings, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_getGreeting()}, ${widget.userName}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Balance', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  _currencyFormat.format(_totalBalance),
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildIncomeExpenseStats(Icons.trending_up, 'Income', _currencyFormat.format(_totalIncome), const Color(0xFF10B981)),
                    _buildIncomeExpenseStats(Icons.trending_down, 'Expenses', _currencyFormat.format(_totalExpense), const Color(0xFFEF4444)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(10, (index) {
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: _weeklyHeights[index],
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.35),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeExpenseStats(IconData icon, String label, String amount, Color iconBg) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconBg.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconBg, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(amount, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildSpendingInsights() {
    final screenWidth = MediaQuery.of(context).size.width;
    final useVerticalLayout = screenWidth < 380;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Spending Insights', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                if (useVerticalLayout) ...[
                  Center(
                    child: SizedBox(
                      height: 120,
                      width: 120,
                      child: CustomPaint(painter: DonutChartPainter(categoryTotals: _categoryTotals, totalExpense: _totalExpense)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      _buildLegendItem('Food', _currencyFormat.format(_categoryTotals['Food']), const Color(0xFF8C3CFF)),
                      _buildLegendItem('Transport', _currencyFormat.format(_categoryTotals['Transport']), const Color(0xFF2E62FF)),
                      _buildLegendItem('Bills', _currencyFormat.format(_categoryTotals['Bills']), const Color(0xFF00BCC9)),
                      _buildLegendItem('Shopping', _currencyFormat.format(_categoryTotals['Shopping']), const Color(0xFF00C853)),
                      _buildLegendItem('Others', _currencyFormat.format(_categoryTotals['Others']), const Color(0xFFFFB300)),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      SizedBox(
                        height: 120,
                        width: 120,
                        child: CustomPaint(painter: DonutChartPainter(categoryTotals: _categoryTotals, totalExpense: _totalExpense)),
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: Column(
                          children: [
                            _buildLegendItem('Food', _currencyFormat.format(_categoryTotals['Food']), const Color(0xFF8C3CFF)),
                            _buildLegendItem('Transport', _currencyFormat.format(_categoryTotals['Transport']), const Color(0xFF2E62FF)),
                            _buildLegendItem('Bills', _currencyFormat.format(_categoryTotals['Bills']), const Color(0xFF00BCC9)),
                            _buildLegendItem('Shopping', _currencyFormat.format(_categoryTotals['Shopping']), const Color(0xFF00C853)),
                            _buildLegendItem('Others', _currencyFormat.format(_categoryTotals['Others']), const Color(0xFFFFB300)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.favorite_border, color: Colors.purple, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _isAiLoading
                            ? Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'AI is analyzing your spending patterns...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.purple.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                _aiInsight,
                                style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, String amount, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 5, backgroundColor: color),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ],
          ),
          Text(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Transactions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TransactionsPage()),
                  ).then((_) => _fetchTransactions());
                },
                child: const Text('See All', style: TextStyle(color: Color(0xFF2E62FF))),
              ),
            ],
          ),
          if (_isLoading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
          if (!_isLoading && _transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text("No transactions yet. Tap the + button to add one!"),
            ),
          if (!_isLoading)
            ..._transactions.take(5).map((t) {
              final isIncome = t['type'] == 'income';
              final amount = (t['amount'] as num).toDouble();
              final date = DateTime.parse(t['created_at']).toLocal();
              final dateFormatted = DateFormat('MMM d, h:mm a').format(date);
              
              IconData icon;
              Color bg;
              Color iconColor;
              switch (t['category']) {
                case 'Food':
                  icon = Icons.restaurant;
                  bg = const Color(0xFFE1BEE7);
                  iconColor = Colors.purple;
                  break;
                case 'Transport':
                  icon = Icons.directions_car;
                  bg = const Color(0xFFB2EBF2);
                  iconColor = Colors.cyan;
                  break;
                case 'Bills':
                  icon = Icons.receipt;
                  bg = const Color(0xFFFFE082);
                  iconColor = Colors.orange;
                  break;
                case 'Shopping':
                  icon = Icons.shopping_bag;
                  bg = const Color(0xFFBBDEFB);
                  iconColor = Colors.blue;
                  break;
                default:
                  icon = isIncome ? Icons.account_balance_wallet : Icons.category;
                  bg = isIncome ? const Color(0xFFC8E6C9) : const Color(0xFFF5F5F5);
                  iconColor = isIncome ? Colors.green : Colors.grey;
              }

              return Dismissible(
                key: Key(t['id'].toString()),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => _deleteTransaction(t['id'].toString()),
                child: InkWell(
                  onTap: () => _showAddTransactionModal(transaction: t),
                  child: _buildTransactionItem(
                    icon,
                    t['title'],
                    dateFormatted,
                    isIncome ? '+${_currencyFormat.format(amount)}' : _currencyFormat.format(amount),
                    t['category'],
                    bg,
                    iconColor,
                    isIncome: isIncome,
                  ),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(IconData icon, String title, String date, String amount, String category, Color bg, Color iconColor, {bool isIncome = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(date, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isIncome ? Colors.green : Colors.black),
              ),
              const SizedBox(height: 4),
              Text(category, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetProgress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Budget Progress', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildProgressBar('Food', _categoryTotals['Food']!, _budgets['Food']!, const Color(0xFF00C853)),
          _buildProgressBar('Transport', _categoryTotals['Transport']!, _budgets['Transport']!, const Color(0xFFFFB300)),
          _buildProgressBar('Bills', _categoryTotals['Bills']!, _budgets['Bills']!, const Color(0xFF00BCC9)),
          _buildProgressBar('Shopping', _categoryTotals['Shopping']!, _budgets['Shopping']!, const Color(0xFF8C3CFF)),
        ],
      ),
    );
  }

  Widget _buildProgressBar(String title, double spent, double limit, Color color) {
    final percent = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final spentStr = _currencyFormat.format(spent);
    final totalStr = _currencyFormat.format(limit);
    final isExceeded = spent > limit;
    final barColor = isExceeded ? const Color(0xFFEF4444) : color;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isExceeded ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExceeded ? Colors.red.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title, 
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isExceeded ? const Color(0xFFB91C1C) : Colors.black87,
                ),
              ),
              Text(
                '$spentStr / $totalStr', 
                style: TextStyle(
                  color: isExceeded ? const Color(0xFFB91C1C) : Colors.grey, 
                  fontSize: 13,
                  fontWeight: isExceeded ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(percent * 100).toInt()}% used', 
                style: TextStyle(
                  color: isExceeded ? const Color(0xFFB91C1C) : Colors.grey, 
                  fontSize: 12,
                ),
              ),
              if (isExceeded)
                const Text(
                  '⚠️ Exceeded!',
                  style: TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isSelected ? const Color(0xFF634DFF) : Colors.grey),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: isSelected ? const Color(0xFF634DFF) : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}

class DonutChartPainter extends CustomPainter {
  final Map<String, double> categoryTotals;
  final double totalExpense;

  DonutChartPainter({required this.categoryTotals, required this.totalExpense});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 24.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    double startAngle = -pi / 2;
    
    final segments = [
      MapEntry(totalExpense == 0 ? 0 : categoryTotals['Food']! / totalExpense, const Color(0xFF8C3CFF)),
      MapEntry(totalExpense == 0 ? 0 : categoryTotals['Transport']! / totalExpense, const Color(0xFF2E62FF)),
      MapEntry(totalExpense == 0 ? 0 : categoryTotals['Bills']! / totalExpense, const Color(0xFF00BCC9)),
      MapEntry(totalExpense == 0 ? 0 : categoryTotals['Shopping']! / totalExpense, const Color(0xFF00C853)),
      MapEntry(totalExpense == 0 ? 0 : categoryTotals['Others']! / totalExpense, const Color(0xFFFFB300)),
    ];

    if (totalExpense == 0) {
      paint.color = Colors.grey.withOpacity(0.2);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), 0, 2 * pi, false, paint);
      return;
    }

    for (var segment in segments) {
      if (segment.key <= 0) continue;
      final sweepAngle = segment.key * 2 * pi;
      paint.color = segment.value;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle - (segments.where((s) => s.key > 0).length > 1 ? 0.05 : 0),
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
