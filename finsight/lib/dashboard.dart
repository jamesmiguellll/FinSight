import 'package:flutter/material.dart';
import 'dart:math';
import 'profile.dart';

class HomePage extends StatefulWidget {
  final String userName;

  const HomePage({super.key, required this.userName});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;


Widget _buildDashboardView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildQuickActions(),
          const SizedBox(height: 32),
          _buildSpendingInsights(),
          const SizedBox(height: 32),
          _buildRecentTransactions(),
          const SizedBox(height: 32),
          _buildBudgetProgress(),
          const SizedBox(height: 40), // Bottom padding
        ],
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    // This list holds the screens for your bottom navigation
    final List<Widget> screens = [
      _buildDashboardView(), // Index 0: Home
      const Center(child: Text('Analytics Coming Soon')), // Index 1: Analytics
      const Center(child: Text('Budget Coming Soon')), // Index 2: Budget
      const ProfilePage(), // Index 3: Profile!
    ];

    

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      
      // Keep your floating action button exactly the same
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF634DFF),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      
      // Keep your bottom navigation bar exactly the same
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
              const SizedBox(width: 48), // Space for the FAB
              _buildNavItem(Icons.track_changes_outlined, 'Budget', 2),
              _buildNavItem(Icons.person_outline, 'Profile', 3),
            ],
          ),
        ),
      ),

      body: screens[_currentIndex], 
    );
  }

  // --- UI SECTION BUILDERS ---

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
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.2),
                child: const Icon(Icons.person, color: Colors.white),
              )
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Good morning, ${widget.userName}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 24),
          
          // Total Balance Card
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
                const Text(
                  '₱12,450.00',
                  style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildIncomeExpenseStats(Icons.trending_up, 'Income', '₱5,200', const Color(0xFF10B981)),
                    _buildIncomeExpenseStats(Icons.trending_down, 'Expenses', '₱3,850', const Color(0xFFEF4444)),
                  ],
                ),
                const SizedBox(height: 16),
                // Faux Bar Chart
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(10, (index) {
                    final heights = [15.0, 25.0, 15.0, 30.0, 20.0, 35.0, 25.0, 40.0, 25.0, 30.0];
                    return Container(
                      width: 24,
                      height: heights[index],
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    );
                  }),
                )
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
          decoration: BoxDecoration(color: iconBg.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: iconBg, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(amount, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        )
      ],
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildActionBtn(Icons.add, 'Expense', const Color(0xFFFF4081)),
          _buildActionBtn(Icons.trending_up, 'Income', const Color(0xFF00C853)),
          _buildActionBtn(Icons.qr_code_scanner, 'Scan', const Color(0xFF8C3CFF)),
          _buildActionBtn(Icons.grid_view, 'Budget', const Color(0xFF00B0FF)),
        ],
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, String label, Color color) {
    return Column(
      children: [
        Container(
          height: 60,
          width: 60,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
      ],
    );
  }

  Widget _buildSpendingInsights() {
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
                Row(
                  children: [
                    // Donut Chart Graphic
                    SizedBox(
                      height: 120,
                      width: 120,
                      child: CustomPaint(painter: DonutChartPainter()),
                    ),
                    const SizedBox(width: 32),
                    // Legend
                    Expanded(
                      child: Column(
                        children: [
                          _buildLegendItem('Food', '₱1200', const Color(0xFF8C3CFF)),
                          _buildLegendItem('Transport', '₱850', const Color(0xFF2E62FF)),
                          _buildLegendItem('Bills', '₱950', const Color(0xFF00BCC9)),
                          _buildLegendItem('Shopping', '₱600', const Color(0xFF00C853)),
                          _buildLegendItem('Others', '₱250', const Color(0xFFFFB300)),
                        ],
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 24),
                // AI Insight Banner
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
                      const Expanded(
                        child: Text(
                          'AI Insight: You spent 20% more on food this week. Consider meal planning to save more!',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      )
                    ],
                  ),
                )
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
                onPressed: () {},
                child: const Text('See All', style: TextStyle(color: Color(0xFF2E62FF))),
              )
            ],
          ),
          _buildTransactionItem(Icons.coffee, 'Starbucks', 'Today, 2:45 PM', '₱5.50', 'Food', const Color(0xFFE1BEE7), Colors.purple),
          _buildTransactionItem(Icons.shopping_cart, 'Amazon', 'Today, 11:20 AM', '₱125.00', 'Shopping', const Color(0xFFBBDEFB), Colors.blue),
          _buildTransactionItem(Icons.account_balance_wallet, 'Salary', 'Yesterday', '+₱2500.00', 'Income', const Color(0xFFC8E6C9), Colors.green, isIncome: true),
          _buildTransactionItem(Icons.directions_car, 'Uber', 'Yesterday', '₱18.00', 'Transport', const Color(0xFFB2EBF2), Colors.cyan),
          _buildTransactionItem(Icons.electric_bolt, 'Electric Bill', 'Apr 7', '₱95.00', 'Bills', const Color(0xFFFFE082), Colors.orange),
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
          )
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
          _buildProgressBar('Food', '₱3,000', '₱5,000', 0.6, const Color(0xFF00C853)),
          _buildProgressBar('Transport', '₱850', '₱1,000', 0.85, const Color(0xFFFFB300)),
          _buildProgressBar('Shopping', '₱1,800', '₱2,000', 0.90, const Color(0xFFFFB300)),
          _buildProgressBar('Entertainment', '₱450', '₱500', 0.90, const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _buildProgressBar(String title, String spent, String total, double percent, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('$spent / $total', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text('${(percent * 100).toInt()}% used', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? const Color(0xFF634DFF) : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          )
        ],
      ),
    );
  }
}

// Custom Painter to draw the static Donut Chart exactly like the image
class DonutChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 24.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt; // Flat edges like the design

    double startAngle = -pi / 2; // Start at the top

    // Define segments: (Percentage, Color)
    final segments = [
      MapEntry(0.35, const Color(0xFF8C3CFF)), // Food
      MapEntry(0.15, const Color(0xFF2E62FF)), // Transport
      MapEntry(0.20, const Color(0xFF00BCC9)), // Bills
      MapEntry(0.20, const Color(0xFF00C853)), // Shopping
      MapEntry(0.10, const Color(0xFFFFB300)), // Others
    ];

    for (var segment in segments) {
      final sweepAngle = segment.key * 2 * pi;
      paint.color = segment.value;
      
      // Draw arc with a tiny gap (0.05 radians) between segments
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle - 0.05, 
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}