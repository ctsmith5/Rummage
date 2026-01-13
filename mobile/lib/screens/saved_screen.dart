import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/favorite_service.dart';
import '../theme/app_colors.dart';
import '../widgets/sale_card.dart';
import 'sale_details_screen.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  int _snackSeq = 0;

  void dismissCurrentSnackBar(ScaffoldMessengerState messenger) {
    // Use the animated dismissal (as opposed to removing instantly).
    messenger.hideCurrentSnackBar();
  }

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favoriteService = context.read<FavoriteService>();
    await favoriteService.loadFavorites();
    await favoriteService.loadFavoritedSales();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // NOTE: This screen is hosted inside an IndexedStack under the HomeScreen's Scaffold.
    // Avoid creating a nested Scaffold here; otherwise SnackBars shown while this tab is
    // active can become "sticky" when switching tabs (Offstage tickers pause animations).
    return Consumer<FavoriteService>(
      builder: (context, favoriteService, _) {
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

        final favoritedSales = favoriteService.favoritedSales;

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

                    final messenger = ScaffoldMessenger.of(context);
                    messenger.clearSnackBars();

                    // Guard against older timers dismissing a newer snackbar.
                    final seq = ++_snackSeq;
                    const snackDuration = Duration(seconds: 3);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('${sale.title} removed from favorites'),
                        duration: snackDuration,
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () {
                            favoriteService.addFavorite(sale.id);
                            dismissCurrentSnackBar(messenger);
                          },
                        ),
                      ),
                    );

                    // Hard guarantee dismissal even if the framework's internal timer doesn't tick.
                    Future.delayed(snackDuration, () {
                      if (!mounted) return;
                      if (seq != _snackSeq) return;
                      dismissCurrentSnackBar(messenger);
                    });
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
    );
  }
}

