import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/sales_service.dart';
import '../theme/app_colors.dart';
import '../widgets/sale_card.dart';
import 'create_sale_screen.dart';
import 'sale_details_screen.dart';

class MySalesScreen extends StatefulWidget {
  const MySalesScreen({super.key});

  @override
  State<MySalesScreen> createState() => _MySalesScreenState();
}

class _MySalesScreenState extends State<MySalesScreen> {
  @override
  void initState() {
    super.initState();
    // Defer to after first build so Provider is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalesService>().loadMySales();
    });
  }

  Future<void> _refresh() async {
    await context.read<SalesService>().loadMySales();
  }

  Future<void> _createSale() async {
    final created = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateSaleScreen(),
      ),
    );

    if (!mounted) return;
    if (created == null) return;

    await _refresh();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sale created'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SalesService, AuthService>(
      builder: (context, salesService, authService, _) {
        final user = authService.currentUser;
        if (user == null) {
          return const Center(child: Text('Log in to view your sales.'));
        }

        if (salesService.isMySalesLoading && salesService.mySales.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final error = salesService.mySalesError;
        if (error != null && error.isNotEmpty && salesService.mySales.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final mine = salesService.mySales
            .where((s) => s.userId == user.id)
            .toList();

        Widget body;
        if (mine.isEmpty) {
          body = RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Text(
                    'No sales yet.\nTap Create Sale to make one.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        } else {
          body = RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
              itemCount: mine.length,
              itemBuilder: (context, index) {
                final sale = mine[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SaleCard(
                    sale: sale,
                    onTap: () async {
                      // Grab messenger before the async gap to satisfy analyzer.
                      final messenger = ScaffoldMessenger.of(context);
                      final deletedSaleId = await Navigator.of(context).push<String?>(
                        MaterialPageRoute(
                          builder: (_) => SaleDetailsScreen(saleId: sale.id),
                        ),
                      );

                      if (mounted) {
                        await _refresh();
                      }
                      if (!mounted) return;

                      if (deletedSaleId == sale.id) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Sale deleted'),
                            backgroundColor: AppColors.success,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
          );
        }

        return Stack(
          children: [
            body,
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _createSale,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Create Sale'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

