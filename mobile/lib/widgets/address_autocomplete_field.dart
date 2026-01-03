import 'dart:async';
import 'package:flutter/material.dart';

import '../services/places_service.dart';
import '../theme/app_colors.dart';

/// A text field with Google Places autocomplete for addresses
class AddressAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final void Function(PlaceDetails details)? onPlaceSelected;
  final double? userLatitude;
  final double? userLongitude;
  final String? labelText;
  final String? hintText;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    this.validator,
    this.onPlaceSelected,
    this.userLatitude,
    this.userLongitude,
    this.labelText = 'Address',
    this.hintText = 'Start typing an address...',
  });

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  List<PlacePrediction> _predictions = [];
  bool _isLoading = false;
  Timer? _debounce;
  String _sessionToken = '';
  bool _ignoreNextChange = false;

  @override
  void initState() {
    super.initState();
    _sessionToken = PlacesService.generateSessionToken();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    if (_ignoreNextChange) {
      _ignoreNextChange = false;
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchPredictions(widget.controller.text);
    });
  }

  Future<void> _fetchPredictions(String input) async {
    if (input.length < 3) {
      setState(() {
        _predictions = [];
      });
      _removeOverlay();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final predictions = await PlacesService.getAutocompletePredictions(
      input,
      sessionToken: _sessionToken,
      latitude: widget.userLatitude,
      longitude: widget.userLongitude,
    );

    if (!mounted) return;

    setState(() {
      _predictions = predictions;
      _isLoading = false;
    });

    if (_predictions.isNotEmpty && _focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: context.findRenderObject() != null
            ? (context.findRenderObject() as RenderBox).size.width
            : 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.2),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _predictions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final prediction = _predictions[index];
                    return _PredictionTile(
                      prediction: prediction,
                      onTap: () => _onPredictionSelected(prediction),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _onPredictionSelected(PlacePrediction prediction) async {
    _removeOverlay();

    // Set the text without triggering another search
    _ignoreNextChange = true;
    widget.controller.text = prediction.description;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );

    // Fetch place details to get coordinates
    final details = await PlacesService.getPlaceDetails(
      prediction.placeId,
      sessionToken: _sessionToken,
    );

    // Generate new session token for next search
    _sessionToken = PlacesService.generateSessionToken();

    if (details != null) {
      widget.onPlaceSelected?.call(details);
    }

    // Unfocus the field
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.location_on_outlined),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        widget.controller.clear();
                        setState(() {
                          _predictions = [];
                        });
                        _removeOverlay();
                      },
                    )
                  : null,
        ),
        validator: widget.validator,
        textInputAction: TextInputAction.done,
      ),
    );
  }
}

class _PredictionTile extends StatelessWidget {
  final PlacePrediction prediction;
  final VoidCallback onTap;

  const _PredictionTile({
    required this.prediction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.place,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prediction.mainText,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDarkMode
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (prediction.secondaryText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      prediction.secondaryText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

