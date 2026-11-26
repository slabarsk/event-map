import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/catalog.dart';
import '../../../core/config/env.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/common.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../events/domain/event_format.dart';
import '../../map/presentation/map_screen.dart' show izmirCenter;
import '../application/organizer_providers.dart';
import '../data/organizer_repository.dart';
import '../domain/organizer_event.dart';

/// Organizatörün etkinlik gönderme formu. Gönderilen etkinlik admin onayına
/// kadar yalnızca organizatöre görünür. Saatler İzmir saatiyle girilir.
class SubmitEventScreen extends ConsumerStatefulWidget {
  const SubmitEventScreen({super.key, this.showTiles = true, this.now});

  /// Testlerde ağ isteği atmamak için kapatılır.
  final bool showTiles;

  /// Testlerde sabit "şimdi".
  final DateTime? now;

  @override
  ConsumerState<SubmitEventScreen> createState() => _SubmitEventScreenState();
}

enum _VenueMode { existing, create }

class _SubmitEventScreenState extends ConsumerState<SubmitEventScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _venueQuery = TextEditingController();
  final _venueName = TextEditingController();
  final _venueAddress = TextEditingController();
  final _priceMin = TextEditingController();
  final _priceMax = TextEditingController();
  final _ticketUrl = TextEditingController();

  String? _category;
  late DateTime _day; // İzmir takvim günü (yalnızca y/m/d)
  TimeOfDay _start = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay? _end;
  _VenueMode _venueMode = _VenueMode.existing;
  VenueOption? _venue;
  List<VenueOption> _venueResults = const [];
  LatLng? _pin;
  bool _free = false;
  bool _registration = false;
  bool _submitting = false;
  Timer? _debounce;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final local = EventFormat.toIstanbul(_now).add(const Duration(days: 1));
    _day = DateTime(local.year, local.month, local.day);
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _venueQuery,
      _venueName,
      _venueAddress,
      _priceMin,
      _priceMax,
      _ticketUrl,
    ]) {
      c.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  /// İzmir duvar saatini UTC ana çevirir.
  DateTime _instant(DateTime day, TimeOfDay t) => DateTime.utc(
    day.year,
    day.month,
    day.day,
    t.hour,
    t.minute,
  ).subtract(EventFormat.istanbulOffset);

  DateTime get _startsAt => _instant(_day, _start);

  /// Bitiş saati başlangıçtan önceyse ertesi güne sarkar (gece etkinlikleri).
  DateTime? get _endsAt {
    final end = _end;
    if (end == null) return null;
    final sameDay = _instant(_day, end);
    return sameDay.isAfter(_startsAt)
        ? sameDay
        : sameDay.add(const Duration(days: 1));
  }

  void _searchVenues(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await ref
            .read(organizerRepositoryProvider)
            .searchVenues(q);
        if (mounted) setState(() => _venueResults = results);
      } on OrganizerFailure {
        if (mounted) setState(() => _venueResults = const []);
      }
    });
  }

  static double? _price(String s) =>
      double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

  String? _validate() {
    if (_category == null) return 'Bir kategori seç.';
    if (!_startsAt.isAfter(_now)) return 'Başlangıç saati gelecekte olmalı.';
    if (_venueMode == _VenueMode.existing && _venue == null) {
      return 'Kayıtlı bir mekân seç ya da yeni mekân ekle.';
    }
    if (_venueMode == _VenueMode.create) {
      if (_venueName.text.trim().isEmpty) return 'Mekân adını yaz.';
      if (_pin == null) return 'Mekânın yerini haritada işaretle.';
    }
    if (!_free) {
      final min = _price(_priceMin.text);
      final max = _price(_priceMax.text);
      if (min != null && max != null && min > max) {
        return 'En düşük fiyat en yüksekten büyük olamaz.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final problem = _validate();
    if (problem != null) {
      showMessage(context, problem, error: true);
      return;
    }
    final creating = _venueMode == _VenueMode.create;
    final draft = EventDraft(
      title: _title.text.trim(),
      category: _category!,
      startsAt: _startsAt,
      endsAt: _endsAt,
      description: _description.text.trim().ifEmptyNull,
      venueId: creating ? null : _venue!.id,
      venueName: creating ? _venueName.text.trim() : null,
      venueAddress: creating ? _venueAddress.text.trim().ifEmptyNull : null,
      lat: creating ? _pin!.latitude : null,
      lng: creating ? _pin!.longitude : null,
      isFree: _free,
      priceMin: _free ? null : _price(_priceMin.text),
      priceMax: _free ? null : _price(_priceMax.text),
      ticketUrl: _ticketUrl.text.trim().ifEmptyNull,
      requiresRegistration: _registration,
    );
    setState(() => _submitting = true);
    try {
      await ref.read(organizerRepositoryProvider).submit(draft);
      if (!mounted) return;
      refreshOrganizer(ref);
      showMessage(context, 'Etkinliğin onaya gönderildi');
      context.canPop() ? context.pop() : context.go(Routes.home);
    } on OrganizerFailure catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickDay() async {
    final today = EventFormat.toIstanbul(_now);
    final first = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(first) ? first : _day,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime({required bool end}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: end
          ? (_end ?? _start.replacing(hour: (_start.hour + 2) % 24))
          : _start,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => end ? _end = picked : _start = picked);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = AppColors.accentFor(UserRole.organizer);
    String hm(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Geri',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        title: Text(trUpper('Etkinlik gönder')),
      ),
      body: AuroraBackground(
        colors: AppColors.blobsFor(UserRole.organizer),
        intensity: 0.6,
        child: SafeArea(
          child: Material(
            type: MaterialType.transparency,
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  MaxWidth(
                    width: 560,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Etkinliğin admin onayından sonra haritada yayınlanır.',
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SectionLabel('Etkinlik'),
                        TextFormField(
                          key: const ValueKey('event-title'),
                          controller: _title,
                          maxLength: 120,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Etkinlik adı',
                            counterText: '',
                          ),
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'Etkinlik adı gerekli'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _description,
                          maxLines: 4,
                          minLines: 2,
                          maxLength: 1000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Açıklama (isteğe bağlı)',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Kategori', style: text.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in Catalog.categories)
                              CategoryChip(
                                category: c,
                                selected: _category == c.id,
                                onTap: () => setState(() => _category = c.id),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const SectionLabel('Tarih ve saat (İzmir)'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _PickerChip(
                              icon: Icons.calendar_today_rounded,
                              label: DateFormat(
                                'd MMMM y EEEE',
                                'tr',
                              ).format(_day),
                              onTap: _pickDay,
                            ),
                            _PickerChip(
                              icon: Icons.schedule_rounded,
                              label: 'Başlangıç ${hm(_start)}',
                              onTap: () => _pickTime(end: false),
                            ),
                            _PickerChip(
                              icon: Icons.timelapse_rounded,
                              label: _end == null
                                  ? 'Bitiş ekle'
                                  : 'Bitiş ${hm(_end!)}',
                              onTap: () => _pickTime(end: true),
                              onClear: _end == null
                                  ? null
                                  : () => setState(() => _end = null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const SectionLabel('Mekân'),
                        PillSelector<_VenueMode>(
                          options: _VenueMode.values,
                          value: _venueMode,
                          accent: accent,
                          labelOf: (m) => switch (m) {
                            _VenueMode.existing => 'Kayıtlı mekân',
                            _VenueMode.create => 'Yeni mekân',
                          },
                          onChanged: (m) => setState(() => _venueMode = m),
                        ),
                        const SizedBox(height: 12),
                        if (_venueMode == _VenueMode.existing)
                          ..._existingVenue(text)
                        else
                          ..._newVenue(text),
                        const SizedBox(height: 24),
                        const SectionLabel('Fiyat ve katılım'),
                        GlassCard(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          // ListTile mürekkebi GlassCard'ın arka planında kaybolmasın.
                          child: Material(
                            type: MaterialType.transparency,
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: const Text('Ücretsiz'),
                                  value: _free,
                                  onChanged: (v) => setState(() => _free = v),
                                ),
                                SwitchListTile(
                                  title: const Text('Başvuru / ön kayıt ile'),
                                  subtitle: const Text(
                                    'Bilet yerine form ya da kontenjanla katılım',
                                  ),
                                  value: _registration,
                                  onChanged: (v) =>
                                      setState(() => _registration = v),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!_free) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _priceField(_priceMin, 'En düşük ₺'),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _priceField(_priceMax, 'En yüksek ₺'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Fiyatı bilmiyorsan boş bırak.',
                            style: text.bodySmall?.copyWith(
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _ticketUrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText:
                                'Bilet / başvuru bağlantısı (isteğe bağlı)',
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            final uri = Uri.tryParse(s);
                            return uri != null &&
                                    (uri.scheme == 'https' ||
                                        uri.scheme == 'http') &&
                                    uri.host.isNotEmpty
                                ? null
                                : 'https:// ile başlayan bir bağlantı gir';
                          },
                        ),
                        const SizedBox(height: 28),
                        PrimaryButton(
                          label: 'Onaya gönder',
                          icon: Icons.send_rounded,
                          busy: _submitting,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _priceField(TextEditingController c, String label) => TextFormField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(labelText: label),
  );

  List<Widget> _existingVenue(TextTheme text) {
    final selected = _venue;
    if (selected != null) {
      return [
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_rounded, color: AppColors.coral),
              title: Text(selected.name),
              subtitle: selected.address == null
                  ? null
                  : Text(selected.address!),
              trailing: IconButton(
                tooltip: 'Mekânı değiştir',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _venue = null),
              ),
            ),
          ),
        ),
      ];
    }
    return [
      TextField(
        key: const ValueKey('venue-search'),
        controller: _venueQuery,
        onChanged: _searchVenues,
        decoration: const InputDecoration(
          labelText: 'Mekân ara',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      for (final v in _venueResults)
        ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(v.name),
          subtitle: v.address == null ? null : Text(v.address!),
          onTap: () => setState(() {
            _venue = v;
            _venueResults = const [];
          }),
        ),
      if (_venueQuery.text.trim().length >= 2 && _venueResults.isEmpty)
        TextButton.icon(
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Bulamadın mı? Yeni mekân ekle'),
          onPressed: () => setState(() {
            _venueMode = _VenueMode.create;
            _venueName.text = _venueQuery.text.trim();
          }),
        ),
    ];
  }

  List<Widget> _newVenue(TextTheme text) => [
    TextField(
      key: const ValueKey('venue-name'),
      controller: _venueName,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Mekân adı'),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _venueAddress,
      decoration: const InputDecoration(labelText: 'Adres (isteğe bağlı)'),
    ),
    const SizedBox(height: 12),
    Text(
      _pin == null
          ? 'Haritada mekânın yerine dokun.'
          : 'Konum işaretlendi. Değiştirmek için başka bir yere dokun.',
      style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
    ),
    const SizedBox(height: 8),
    ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 240,
        child: FlutterMap(
          key: const ValueKey('venue-map'),
          options: MapOptions(
            initialCenter: _pin ?? izmirCenter,
            initialZoom: 12,
            minZoom: 8,
            maxZoom: 18,
            backgroundColor: const Color(0xFFF4EEEA),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: (_, point) => setState(() => _pin = point),
          ),
          children: [
            if (widget.showTiles)
              TileLayer(
                urlTemplate: Env.hasMapbox
                    ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                additionalOptions: Env.hasMapbox
                    ? const {'accessToken': Env.mapboxPublicToken}
                    : const {},
                userAgentPackageName: 'com.eventmap.event_map',
              ),
            if (_pin != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pin!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 40,
                      color: AppColors.coral,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  ];
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      onDeleted: onClear,
      deleteButtonTooltipMessage: 'Kaldır',
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
