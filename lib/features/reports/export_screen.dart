import '../../core/report_years.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Border, BorderStyle;
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel_community/excel_community.dart';
import '../../core/theme.dart';
import '../../models/entities.dart';
import '../../services/session.dart';
import '../../services/report_scope.dart';
import '../../services/report_tables.dart';
import '../auth/login_screen.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key,required this.session,this.initialFormat='PDF'});final Session session;final String initialFormat;
  @override State<ExportScreen> createState()=>_ExportScreenState();
}
class _ExportScreenState extends State<ExportScreen> {
  late Future<List<Object>> data;
  String format='PDF',report='Officer Performance (Target Summary)';
  int year=DateTime.now().year,month=DateTime.now().month;
  bool allMonths=false,monthRange=false,includeZone=true,includeManager=true,busy=false;
  int fromMonth=1,toMonth=6;
  String selectedOfficer='ALL';
  @override void initState(){super.initState();format=widget.initialFormat;reload();
    _updates=widget.session.api.watchRankingCounts().listen((_) => _liveRefresh(), onError: (_) {});}
  StreamSubscription<Map<String, int>>? _updates;
  Timer? _debounce;
  void _liveRefresh() {
    _debounce?.cancel();
    _debounce=Timer(const Duration(milliseconds: 650), () {
      if(mounted) setState(reload);
    });
  }
  @override void dispose() {
    _debounce?.cancel();_updates?.cancel();
    
    super.dispose();
  }
  void reload() {
    data = Future.wait<Object>([
      widget.session.api.employees(),
      widget.session.api.records(),
      widget.session.api.targets(),
    ]);
  }
  String effectiveOfficer(List<Object> results) {
    if (selectedOfficer == 'ALL') { return 'ALL'; }
    final officers = permittedReportOfficers(widget.session.user!,
      results[0] as List<Employee>);
    return officers.any((e) => e.employeeId == selectedOfficer)
        ? selectedOfficer : 'ALL';
  }

  List<List<String>> rows(List<Object> results) => buildReportTable(
    viewer: widget.session.user!,
    employees: results[0] as List<Employee>,
    records: results[1] as List<CardRecord>,
    reportType: report,
    selectedOfficer: effectiveOfficer(results),
    year: year, month: month,
    allMonths: allMonths,
    includeZone: includeZone,
    includeManager: includeManager,
    fromMonth: monthRange && !allMonths ? fromMonth : null,
    toMonth: monthRange && !allMonths ? toMonth : null,
  );

  String get periodLabel => allMonths ? 'January - December $year (Yearly Target)'
      : monthRange ? '${monthNames[fromMonth - 1]} - ${monthNames[toMonth - 1]} '
          '$year (Monthly Target x ${toMonth - fromMonth + 1})'
      : '${monthNames[month - 1]} $year (Monthly Target)';

  pw.Widget _styledPdfTable(List<List<String>> rows) {
    final headers = rows.first;
    final achievementColumn = headers.indexOf('Achievement');
    final boldColumns = {'Total', 'Target', 'SHORT'};
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        for (var c = 0; c < headers.length; c++) c: pw.FlexColumnWidth(
          headers[c] == 'Branch' ? 2.4 : headers[c] == 'Branch Official' ? 2.5
          : headers[c] == 'Sales Manager' ? 2.3 : headers[c] == 'Zone' ? 1.0
          : headers[c] == 'Achievement' ? 1.3 : 0.9),
      },
      children: [
        for (var r = 0; r < rows.length; r++)
          pw.TableRow(children: [
            for (var c = 0; c < headers.length; c++)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                alignment: c == 0 || c == 1 || headers[c] == 'Sales Manager'
                    ? pw.Alignment.centerLeft : pw.Alignment.center,
                child: pw.Text(rows[r][c],
                  style: pw.TextStyle(fontSize: r == 0 ? 8 : 7.3,
                    fontWeight: r == 0 || c == 1 || boldColumns.contains(headers[c])
                        ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: r > 0 && c == achievementColumn
                        ? PdfColor.fromHex('#24865B') : PdfColors.black),
                  textAlign: c == 0 || c == 1 || headers[c] == 'Sales Manager'
                      ? pw.TextAlign.left : pw.TextAlign.center,
                ),
              ),
          ]),
      ],
    );
  }

  Future<Uint8List> buildFile(List<List<String>> rows) async {
    if (format == 'Excel') {
      final excel = Excel.createExcel();
      final sheet = excel['Performance'];
      excel.delete('Sheet1');
      final borders = Border(borderStyle: BorderStyle.Thin);
      final headStyle = CellStyle(
        bold: true, fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        backgroundColorHex: ExcelColor.fromHexString('#EDF3EF'),
        fontColorHex: ExcelColor.fromHexString('#1C1F1D'),
        leftBorder: borders, rightBorder: borders,
        topBorder: borders, bottomBorder: borders);
      final textStyle = CellStyle(
        fontSize: 10, verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: borders, rightBorder: borders,
        topBorder: borders, bottomBorder: borders);
      final strongStyle = CellStyle(
        bold: true, fontSize: 10, horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: borders, rightBorder: borders,
        topBorder: borders, bottomBorder: borders);
      final percentageStyle = CellStyle(
        bold: true, fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('#24865B'),
        horizontalAlign: HorizontalAlign.Center,
        leftBorder: borders, rightBorder: borders,
        topBorder: borders, bottomBorder: borders);
      // Exactly the grid columns in the supplied six-month reference image.
      final columns = rows.first;
      for (var col = 0; col < columns.length; col++) {
        final heading = columns[col];
        sheet.setColumnWidth(col, heading == 'Branch' ? 35
          : heading == 'Branch Official' ? 31
          : heading == 'Sales Manager' ? 31
          : heading == 'Zone' ? 16 : heading == 'Achievement' ? 18 : 13);
      }
      sheet.setRowHeight(0, 28);
      for (var row = 0; row < rows.length; row++) {
        if (row > 0) sheet.setRowHeight(row, 22);
        for (var col = 0; col < rows[row].length; col++) {
          final heading = columns[col];
          final raw = rows[row][col];
          final index = CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
          final cell = sheet.cell(index);
          final numeric = row > 0 && {'Total', 'Target', 'SHORT'}.contains(heading)
              ? int.tryParse(raw) : null;
          // Account numbers stay text, so leading zeros cannot disappear.
          cell.value = numeric != null ? IntCellValue(numeric)
              : TextCellValue(raw.startsWith('=') || raw.startsWith('+') ||
                   raw.startsWith('@') ? "'$raw" : raw);
          cell.cellStyle = row == 0 ? headStyle
              : heading == 'Achievement' ? percentageStyle
              : numeric != null ? strongStyle : textStyle;
        }
      }
      final bytes = excel.save();
      if (bytes == null) throw StateError('XLSX generation failed');
      return Uint8List.fromList(bytes);
    }

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(25),
      build: (context) => [
        pw.Center(child: pw.Text('PERFORMANCE TRACKER',
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 5),
        pw.Center(child: pw.Text(report,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text(periodLabel, style: const pw.TextStyle(fontSize: 9))),
        pw.SizedBox(height: 12),
        _styledPdfTable(rows),
      ],
      footer: (context) => pw.Align(alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8))),
    ));
    return Uint8List.fromList(await doc.save());
  }

  Future<void> export(bool preview) async {
    setState(()=>busy=true);
    try {
      final raw=await data;final table=rows(raw);
      if(table.length==1)throw const FormatException('No data matches selected scope');
      if(preview){if(!mounted)return;await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>ReportPreviewScreen(rows:table)));return;}
      final bytes=await buildFile(table);
      final extension={'PDF':'pdf','Excel':'xlsx'}[format]!;
      // file_picker 12.x returns Uri? instead of String? for saved files.
      final Uri? destination=await FilePicker.saveFile(dialogTitle:'Save $format Report',fileName:'performance_${effectiveOfficer(raw) == 'ALL' ? 'all' : effectiveOfficer(raw)}_${year}_${allMonths ? 'annual' : monthRange ? '${fromMonth}_to_$toMonth' : month}.$extension',bytes:bytes);
      if(destination==null)return;
      await widget.session.api.auditExport(format);
      if(mounted)showMessage(context,'Report saved: $destination');
    }catch(e){if(mounted)showMessage(context,'Export failed: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> printReport() async {
    if(format!='PDF') {showMessage(context,'Choose PDF format for printing');return;}
    setState(()=>busy=true);
    try{
      final table=rows(await data);
      if(table.length<2) throw const FormatException('No data to print');
      await Printing.layoutPdf(onLayout:(pageFormat)=>buildFile(table));
      await widget.session.api.auditExport('PDF_PRINT');
    }catch(error){if(mounted)showMessage(context,'$error');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Export Reports'),actions:[IconButton(onPressed:()=>setState(reload),icon:const Icon(Icons.refresh))]),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:ListView(padding:const EdgeInsets.all(14),children:[
    SectionCard(child:Column(children:[
      DropdownButtonFormField<String>(initialValue:format,decoration:const InputDecoration(labelText:'Export Format'),items:['PDF','Excel'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>format=v??format)),const SizedBox(height:12),
      DropdownButtonFormField<String>(initialValue:report,decoration:const InputDecoration(labelText:'Report Type'),isExpanded:true,items:['Officer Performance (Target Summary)','Sales Manager Performance','Card Application Details'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>report=v??report)),const SizedBox(height:12),
      Row(children:[
        Expanded(child:DropdownButtonFormField<int>(initialValue:year,decoration:const InputDecoration(labelText:'Year'),items:[for(final y in reportYears)DropdownMenuItem(value:y,child:Text('$y'))],onChanged:(v)=>setState(()=>year=v??year))),
        if(!allMonths && !monthRange) ...[
          const SizedBox(width:8),
          Expanded(child:DropdownButtonFormField<int>(initialValue:month,decoration:const InputDecoration(labelText:'Month'),items:[for(var m=1;m<=12;m++)DropdownMenuItem(value:m,child:Text(monthNames[m-1]))],onChanged:(v)=>setState(()=>month=v??month))),
        ],
      ]),
      const SizedBox(height:14),
      FutureBuilder<List<Object>>(future:data,builder:(context,s){
        if(s.hasError)return Text('Unable to load permitted officers: ${s.error}');
        if(!s.hasData)return const LinearProgressIndicator();
        final available=permittedReportOfficers(widget.session.user!,
          s.data![0] as List<Employee>);
        final effectiveSelection=effectiveOfficer(s.data!);
        return DropdownButtonFormField<String>(key:ValueKey('officer_$selectedOfficer'),
          initialValue: effectiveSelection, isExpanded:true,
          decoration:const InputDecoration(labelText:'Officer / Report Scope', floatingLabelBehavior: FloatingLabelBehavior.always, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 18)),
          items:[const DropdownMenuItem(value:'ALL',child:Text('All permitted officers')),
            for(final e in available) DropdownMenuItem(value:e.employeeId,
              child:Text('${e.name} (${e.employeeId})',overflow:TextOverflow.ellipsis))],
          onChanged:(v)=>setState(()=>selectedOfficer=v??'ALL'));
      }),
      const SizedBox(height:6),
      if(widget.session.user!.role.toLowerCase()=='sales manager')
        const Text('Only officers assigned to your manager ID are included. '
          'Officer List and Ranking remain visible to everyone.',
          style:TextStyle(color:Palette.muted,fontSize:12)),
      SwitchListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        dense: true, value:allMonths,title:const Text('All Months (annual target)'),
        onChanged:(v)=>setState(()=>allMonths=v)),
      if (!allMonths) ...[
        CheckboxListTile(value:monthRange,
          title:const Text('Select Month Range (e.g., January - June)'),
          onChanged:(v)=>setState(()=>monthRange=v??false)),
        if (monthRange) Row(children:[
          Expanded(child:DropdownButtonFormField<int>(initialValue:fromMonth,
            isExpanded:true,decoration:const InputDecoration(labelText:'From Month'),
            items:[for(var m=1;m<=12;m++)DropdownMenuItem(
              value:m,child:Text(monthNames[m-1]))],
            onChanged:(m)=>setState(() {
              fromMonth=m??fromMonth;
              if(toMonth<fromMonth)toMonth=fromMonth;
            }))),
          const SizedBox(width:8),
          Expanded(child:DropdownButtonFormField<int>(
            key:ValueKey('to_$fromMonth'),
            initialValue:toMonth,isExpanded:true,
            decoration:const InputDecoration(labelText:'To Month'),
            items:[for(var m=fromMonth;m<=12;m++)DropdownMenuItem(
              value:m,child:Text(monthNames[m-1]))],
            onChanged:(m)=>setState(()=>toMonth=m??toMonth))),
        ]),
      ],
      CheckboxListTile(value:includeZone,title:const Text('Include Zone'),onChanged:(v)=>setState(()=>includeZone=v??false)),
      CheckboxListTile(value:includeManager,title:const Text('Include Sales Manager'),onChanged:(v)=>setState(()=>includeManager=v??false)),
      FutureBuilder<List<Object>>(future:data,builder:(ctx,s){if(s.hasError)return Text('Unable to preview counts: ${s.error}');if(!s.hasData)return const LinearProgressIndicator();final raw=s.data!;
        final table=rows(raw);
        final count=exportedCardCount(
          viewer: widget.session.user!,
          employees: raw[0] as List<Employee>,
          records: raw[1] as List<CardRecord>,
          selectedOfficer: effectiveOfficer(raw), year: year, month: month,
          allMonths: allMonths,
          fromMonth: monthRange && !allMonths ? fromMonth : null,
          toMonth: monthRange && !allMonths ? toMonth : null);
        return Text('Officer/report rows: ${table.length - 1} • Valid 906 cards: $count');}),
      const SizedBox(height:12),OutlinedButton.icon(onPressed:busy?null:()=>export(true),icon:const Icon(Icons.preview),label:const Text('Preview Report Layout')),
      const SizedBox(height:8),if(format=='PDF')OutlinedButton.icon(onPressed:busy?null:printReport,icon:const Icon(Icons.print_outlined),label:const Text('Print PDF')),
      const SizedBox(height:8),FilledButton.icon(onPressed:busy?null:()=>export(false),icon:const Icon(Icons.download_outlined),label:Text(busy?'Working...':'Download / Save')),
    ])),
  ]))));
}
class ReportPreviewScreen extends StatelessWidget {
  const ReportPreviewScreen({super.key,required this.rows});final List<List<String>> rows;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Report Preview')),body:ListView(padding:const EdgeInsets.all(12),children:[
    SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(columns:[for(final heading in rows.first)DataColumn(label:Text(heading))],rows:[for(final row in rows.skip(1))DataRow(cells:[for(final value in row)DataCell(Text(value))])])),
  ]));
}
