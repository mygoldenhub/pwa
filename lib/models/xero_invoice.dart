class XeroInvoice {
  /// Primary key in `public.invoice`.
  final String invoiceId;
  final String? type;
  final String? invoiceNum;
  final String? reference;
  final double? amountDue;
  final double? amountPaid;
  final double? amountCredited;
  final double? currencyRate;
  final bool? isDiscounted;
  final bool? hasAttachments;
  final Map<String, dynamic>? contact;
  final String? dateString;
  final DateTime? date;
  final String? dueDateString;
  final DateTime? dueDate;
  final String? status;
  final String? lineAmountTypes;
  final double? subTotal;
  final double? totalTax;
  final double? total;
  final DateTime? updatedDateUtc;
  final String? currencyCode;
  final DateTime? fullPaidOnDate;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> lineItems;

  const XeroInvoice({
    required this.invoiceId,
    this.type,
    this.invoiceNum,
    this.reference,
    this.amountDue,
    this.amountPaid,
    this.amountCredited,
    this.currencyRate,
    this.isDiscounted,
    this.hasAttachments,
    this.contact,
    this.dateString,
    this.date,
    this.dueDateString,
    this.dueDate,
    this.status,
    this.lineAmountTypes,
    this.subTotal,
    this.totalTax,
    this.total,
    this.updatedDateUtc,
    this.currencyCode,
    this.fullPaidOnDate,
    this.payments = const <Map<String, dynamic>>[],
    this.lineItems = const <Map<String, dynamic>>[],
  });

  /// Convenience alias used in some UI/service code.
  String get id => invoiceId;

  /// Extracts a contact id from either `contact.contact_id` or other common key variants.
  String? get contactId {
    final c = contact;
    if (c == null) return null;
    final v = c['contact_id'] ?? c['ContactID'] ?? c['contactId'] ?? c['id'] ?? c['ID'];
    return v?.toString();
  }

  /// Convenience for older code that expects a currency string.
  String? get currency => currencyCode;

  /// Convenience for older code that expects `issueDate`.
  DateTime? get issueDate => date;

  XeroInvoice copyWith({
    String? invoiceId,
    String? type,
    String? invoiceNum,
    String? reference,
    double? amountDue,
    double? amountPaid,
    double? amountCredited,
    double? currencyRate,
    bool? isDiscounted,
    bool? hasAttachments,
    Map<String, dynamic>? contact,
    String? dateString,
    DateTime? date,
    String? dueDateString,
    DateTime? dueDate,
    String? status,
    String? lineAmountTypes,
    double? subTotal,
    double? totalTax,
    double? total,
    DateTime? updatedDateUtc,
    String? currencyCode,
    DateTime? fullPaidOnDate,
    List<Map<String, dynamic>>? payments,
    List<Map<String, dynamic>>? lineItems,
  }) {
    return XeroInvoice(
      invoiceId: invoiceId ?? this.invoiceId,
      type: type ?? this.type,
      invoiceNum: invoiceNum ?? this.invoiceNum,
      reference: reference ?? this.reference,
      amountDue: amountDue ?? this.amountDue,
      amountPaid: amountPaid ?? this.amountPaid,
      amountCredited: amountCredited ?? this.amountCredited,
      currencyRate: currencyRate ?? this.currencyRate,
      isDiscounted: isDiscounted ?? this.isDiscounted,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      contact: contact ?? this.contact,
      dateString: dateString ?? this.dateString,
      date: date ?? this.date,
      dueDateString: dueDateString ?? this.dueDateString,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      lineAmountTypes: lineAmountTypes ?? this.lineAmountTypes,
      subTotal: subTotal ?? this.subTotal,
      totalTax: totalTax ?? this.totalTax,
      total: total ?? this.total,
      updatedDateUtc: updatedDateUtc ?? this.updatedDateUtc,
      currencyCode: currencyCode ?? this.currencyCode,
      fullPaidOnDate: fullPaidOnDate ?? this.fullPaidOnDate,
      payments: payments ?? this.payments,
      lineItems: lineItems ?? this.lineItems,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'invoice_id': invoiceId,
      'type': type,
      'invoice_num': invoiceNum,
      'reference': reference,
      'amount_due': amountDue,
      'amount_paid': amountPaid,
      'amount_credited': amountCredited,
      'currency_rate': currencyRate,
      'is_discounted': isDiscounted,
      'has_attachments': hasAttachments,
      'contact': contact,
      'date_string': dateString,
      'date': date?.toIso8601String(),
      'due_date_string': dueDateString,
      'due_date': dueDate?.toIso8601String(),
      'status': status,
      'line_amount_types': lineAmountTypes,
      'sub_total': subTotal,
      'total_tax': totalTax,
      'total': total,
      'updated_date_utc': updatedDateUtc?.toIso8601String(),
      'currency_code': currencyCode,
      'full_paid_on_date': fullPaidOnDate?.toIso8601String(),
      'payments': payments,
      'line_items': lineItems,
    };
  }

  static XeroInvoice? fromJson(dynamic json) {
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json as Map);
    final invoiceId = map['invoice_id']?.toString();
    if (invoiceId == null || invoiceId.isEmpty) return null;

    DateTime? parseDateTime(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    /// For fields that are defined as UTC (e.g. `updated_date_utc`).
    ///
    /// Supabase/PostgREST typically returns ISO8601 with an explicit offset
    /// (e.g. `2024-01-01T12:34:56+00:00`) which `DateTime.tryParse` correctly
    /// interprets as UTC.
    ///
    /// However, some views/functions or older data can return a string without
    /// an offset (e.g. `2024-01-01T12:34:56`). In that case Dart treats it as
    /// *local time*, which would make `toLocal()` a no-op and show the wrong
    /// time on customer devices. We force such values to be interpreted as UTC.
    DateTime? parseUtcDateTime(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) {
        if (v.isUtc) return v;
        return DateTime.utc(v.year, v.month, v.day, v.hour, v.minute, v.second, v.millisecond, v.microsecond);
      }
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) return null;
        final hasExplicitTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s);
        final normalized = hasExplicitTz ? s : '${s}Z';
        return DateTime.tryParse(normalized);
      }
      return null;
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    bool? parseBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      final s = v.toString().toLowerCase();
      if (s == 'true' || s == 't' || s == '1') return true;
      if (s == 'false' || s == 'f' || s == '0') return false;
      return null;
    }

    Map<String, dynamic>? parseJsonObject(dynamic v) {
      if (v == null) return null;
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    List<Map<String, dynamic>> parseJsonListOfObjects(dynamic v) {
      if (v == null) return const <Map<String, dynamic>>[];
      if (v is List) {
        return v.whereType<Object>().map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return const <String, dynamic>{};
        }).where((e) => e.isNotEmpty).toList();
      }
      return const <Map<String, dynamic>>[];
    }

    return XeroInvoice(
      invoiceId: invoiceId,
      type: map['type']?.toString(),
      invoiceNum: map['invoice_num']?.toString(),
      reference: map['reference']?.toString(),
      amountDue: parseDouble(map['amount_due']),
      amountPaid: parseDouble(map['amount_paid']),
      amountCredited: parseDouble(map['amount_credited']),
      currencyRate: parseDouble(map['currency_rate']),
      isDiscounted: parseBool(map['is_discounted']),
      hasAttachments: parseBool(map['has_attachments']),
      contact: parseJsonObject(map['contact']),
      dateString: map['date_string']?.toString(),
      date: parseDateTime(map['date']),
      dueDateString: map['due_date_string']?.toString(),
      dueDate: parseDateTime(map['due_date']),
      status: map['status']?.toString(),
      lineAmountTypes: map['line_amount_types']?.toString(),
      subTotal: parseDouble(map['sub_total']),
      totalTax: parseDouble(map['total_tax']),
      total: parseDouble(map['total']),
      updatedDateUtc: parseUtcDateTime(map['updated_date_utc']),
      currencyCode: map['currency_code']?.toString(),
      fullPaidOnDate: parseDateTime(map['full_paid_on_date']),
      payments: parseJsonListOfObjects(map['payments']),
      lineItems: parseJsonListOfObjects(map['line_items']),
    );
  }
}
