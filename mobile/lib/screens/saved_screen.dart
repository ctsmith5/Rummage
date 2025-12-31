import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/favorite_service.dart';
import '../services/sales_service.dart';
import '../theme/app_colors.dart';
import '../widgets/sale_card.dart';
import 'sale_details_screen.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    await context.read<FavoriteService>().loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Consumer2<FavoriteService, SalesService>(
        builder: (context, favoriteService, salesService, _) {
          if (favoriteService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final favorites = favoriteService.favorites;

          if (favorites.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: isDarkMode
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No saved sales yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the heart icon on a sale to save it',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          // Get the full sale data for each favorite
          final favoritedSales = salesService.sales
              .where((sale) => favoriteService.isFavorited(sale.id))
              .toList();

          return RefreshIndicator(
            onRefresh: _loadFavorites,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: favoritedSales.length,
              itemBuilder: (context, index) {
                final sale = favoritedSales[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Dismissible(
                    key: Key(sale.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete,
                        color: Colors.white,
                      ),
                    ),
                    onDismissed: (_) {
                      favoriteService.removeFavorite(sale.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${sale.title} removed from favorites'),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () {
                              favoriteService.addFavorite(sale.id);
                            },
                          ),
                        ),
                      );
                    },
                    child: SaleCard(
                      sale: sale,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SaleDetailsScreen(saleId: sale.id),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

