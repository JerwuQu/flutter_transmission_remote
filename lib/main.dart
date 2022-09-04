import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart'; // TODO: remove
import 'package:collection/collection.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:jwq_utils/jwq_utils.dart';

import 'transmission.dart';

var settings = SettingManager();

void main() async {
  await settings.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transmission Remote',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.robotoTextTheme(Theme.of(context).textTheme),
      ),
      home: const ConnectionListPage(),
    );
  }
}

class ConnectionInfo {
  bool autoConnect;
  String url, username, password;

  ConnectionInfo.empty()
      : url = '',
        username = '',
        password = '',
        autoConnect = false;

  ConnectionInfo.fromJson(Map<String, dynamic> json)
      : url = json['url'],
        username = json['username'],
        password = json['password'],
        autoConnect = json['auto'] ?? false;
  toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'auto': autoConnect,
      };
}

class SettingManager {
  // TODO: support storing connections encrypted

  late List<ConnectionInfo> connections;

  Future load() async {
    final prefs = await SharedPreferences.getInstance();

    final connectionsJson = jsonDecode(prefs.getString('connections') ?? '[]');
    connections =
        connectionsJson.map<ConnectionInfo>((json) => ConnectionInfo.fromJson(json)).toList();
  }

  Future save() async {
    final prefs = await SharedPreferences.getInstance();

    final connectionsJson = jsonEncode(connections.map((c) => c.toJson()).toList());
    await prefs.setString('connections', connectionsJson);
  }
}

class ConnectionListPage extends StatefulWidget {
  const ConnectionListPage({Key? key}) : super(key: key);

  @override
  State<ConnectionListPage> createState() => ConnectionListPageState();
}

class ConnectionListPageState extends State<ConnectionListPage> {
  @override
  void initState() {
    super.initState();
    final autoConn = settings.connections.firstWhereOrNull((c) => c.autoConnect);
    if (autoConn != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (ctx) => ConnectionPage(conn: autoConn)),
        );
      });
    }
  }

  Future editConnection([int? index]) async {
    ConnectionInfo conn = index == null
        ? ConnectionInfo.empty()
        : ConnectionInfo.fromJson(settings.connections[index].toJson());
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/rpc/',
                      labelText: 'RPC URL (end in /rpc/)',
                    ),
                    initialValue: conn.url,
                    onChanged: (str) => conn.url = str,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Username (optional)'),
                    initialValue: conn.username,
                    onChanged: (str) => conn.username = str,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Password (optional)'),
                    initialValue: conn.password,
                    onChanged: (str) => conn.password = str,
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                          TextButton(
                            style: TextButton.styleFrom(
                              primary: Theme.of(context).colorScheme.primary,
                              backgroundColor: Theme.of(context).colorScheme.surface,
                              elevation: 3,
                              padding: const EdgeInsets.all(8),
                            ),
                            onPressed: () {
                              setState(() {
                                if (index == null) {
                                  settings.connections.add(conn);
                                } else {
                                  settings.connections[index] = conn;
                                }
                                settings.save();
                              });
                              return Navigator.of(context).pop();
                            },
                            child: const Text('Save'),
                          ),
                        ] +
                        (index == null
                            ? []
                            : [
                                const SizedBox(width: 40),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    primary: Colors.red,
                                    backgroundColor: Theme.of(context).colorScheme.surface,
                                    elevation: 3,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  onPressed: () async {
                                    if (await confirm(context)) {
                                      setState(() {
                                        settings.connections.removeAt(index);
                                        settings.save();
                                      });
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: const Text('Delete'),
                                ),
                              ]),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
      ),
      body: ListView(
        controller: AdjustableScrollController(100),
        children: settings.connections
            .mapIndexed<Widget>(
              (index, conn) => ListTile(
                title: Row(children: [
                  IconButton(
                    icon: conn.autoConnect
                        ? const Icon(Icons.auto_awesome)
                        : const Icon(Icons.auto_awesome_outlined),
                    color: conn.autoConnect ? Colors.orange : Colors.grey,
                    onPressed: () {
                      setState(() {
                        for (var c in settings.connections) {
                          c.autoConnect = (c == conn && !c.autoConnect);
                        }
                        settings.save();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(conn.username == '' ? conn.url : '${conn.username}@${conn.url}')),
                ]),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (ctx) => ConnectionPage(conn: conn)),
                  );
                },
                onLongPress: () => editConnection(index),
              ),
            )
            .toList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => editConnection(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class DownloadDirPicker extends StatefulWidget {
  final List<Torrent> torrents;
  final void Function(String) onChanged;
  final String? initialDir;
  const DownloadDirPicker(this.torrents, {required this.onChanged, this.initialDir, Key? key})
      : super(key: key);

  @override
  State<DownloadDirPicker> createState() => DownloadDirPickerState();
}

class DownloadDirPickerState extends State<DownloadDirPicker> {
  final downloadDirController = TextEditingController(text: '');

  @override
  void initState() {
    super.initState();
    downloadDirController.text =
        widget.initialDir ?? widget.torrents.firstOrNull?.downloadDir ?? '';
    widget.onChanged(downloadDirController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PopupMenuButton(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
          tooltip: 'Choose from current torrents',
          itemBuilder: (BuildContext context) {
            return widget.torrents
                .map((t) => t.downloadDir)
                .toSet()
                .map((d) => PopupMenuItem(value: d, child: Text(d)))
                .toList();
          },
          onSelected: (str) {
            setState(() {
              downloadDirController.text = str as String;
              widget.onChanged(str);
            });
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: downloadDirController,
            decoration: const InputDecoration(
              hintText: '~/Download',
              labelText: 'Download directory',
            ),
            onChanged: (str) => widget.onChanged(str),
          ),
        ),
      ],
    );
  }
}

class AddTorrentDialog extends StatefulWidget {
  final List<Torrent> torrents;
  final void Function(Uint8List data, String dir) onAddFromFile;
  final void Function(String url, String dir) onAddByUrl;
  const AddTorrentDialog(
    this.torrents, {
    required this.onAddFromFile,
    required this.onAddByUrl,
    Key? key,
  }) : super(key: key);

  @override
  State<AddTorrentDialog> createState() => AddTorrentDialogState();
}

class AddTorrentDialogState extends State<AddTorrentDialog> {
  bool preferTorrentFile = false;
  String downloadDir = '';

  String torrentUrl = '';

  String pickedFilename = '';
  Uint8List? torrentFileData;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                    const Text('URL'),
                    Radio<bool>(
                      value: false,
                      groupValue: preferTorrentFile,
                      onChanged: (v) => setState(() => preferTorrentFile = v ?? false),
                    ),
                    const Text('File'),
                    Radio<bool>(
                      value: true,
                      groupValue: preferTorrentFile,
                      onChanged: (v) => setState(() => preferTorrentFile = v ?? true),
                    ),
                    const SizedBox(width: 10),
                  ] +
                  (preferTorrentFile
                      ? [
                          TextButton(
                            style: TextButton.styleFrom(
                              primary: Theme.of(context).colorScheme.primary,
                              backgroundColor: Theme.of(context).colorScheme.surface,
                              elevation: 3,
                              padding: const EdgeInsets.all(8),
                            ),
                            onPressed: () async {
                              FilePickerResult? result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['torrent'],
                                withData: true,
                              );
                              if (!mounted) return;
                              if (result == null) {
                                setState(() {
                                  pickedFilename = '';
                                  torrentFileData = null;
                                });
                              } else {
                                if (result.files.first.bytes == null) {
                                  showError(context, 'Failed to load', 'Failed to load the file');
                                  return;
                                }
                                setState(() {
                                  pickedFilename = result.files.first.name;
                                  torrentFileData = result.files.first.bytes!;
                                });
                              }
                            },
                            child: const Text('Pick File'),
                          ),
                          const SizedBox(width: 10),
                          Text(pickedFilename),
                        ]
                      : [
                          Expanded(
                            child: TextFormField(
                              decoration: const InputDecoration(
                                hintText: 'https://...',
                                labelText: 'Torrent URL',
                              ),
                              onChanged: (str) => torrentUrl = str,
                            ),
                          ),
                        ]),
            ),
            DownloadDirPicker(
              widget.torrents,
              onChanged: (dir) => downloadDir = dir,
            ),
            const SizedBox(height: 10),
            TextButton(
              style: TextButton.styleFrom(
                primary: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(context).colorScheme.surface,
                elevation: 3,
                padding: const EdgeInsets.all(8),
              ),
              onPressed: () async {
                if (preferTorrentFile) {
                  if (torrentFileData == null) {
                    await showError(context, 'No file', 'You need to select a file');
                    return;
                  }
                  Navigator.of(context).pop();
                  widget.onAddFromFile(torrentFileData!, downloadDir);
                } else {
                  Navigator.of(context).pop();
                  widget.onAddByUrl(torrentUrl, downloadDir);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  final ConnectionInfo conn;
  const ConnectionPage({required this.conn, Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => ConnectionPageState();
}

class ConnectionPageState extends State<ConnectionPage> {
  Offset tapPos = Offset.zero;
  late TransmissionConnection connection;
  AdjustableScrollController scrollController = AdjustableScrollController(100);
  Future<void> loading = Future.value();

  List<Torrent> allTorrents = [];

  TextEditingController searchController = TextEditingController();
  int? sortColumnIndex;
  bool sortAscending = true;
  int Function(Torrent, Torrent)? sortComparer;
  List<Torrent> filteredStortedTorrents = [];

  @override
  void initState() {
    super.initState();
    ConnectionInfo ci = widget.conn;
    connection = TransmissionConnection(ci.url, ci.username, ci.password);
    refreshTorrents();
  }

  void errorDialog(TransmissionException e) async {
    await showError(context, 'Transmission Error', e.message);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<T?> loadTask<T>(Future<T> task) async {
    await loading;
    setState(() {
      loading = task;
    });
    try {
      return await task;
    } on TransmissionException catch (e) {
      errorDialog(e);
      return null;
    } catch (e) {
      errorDialog(TransmissionException('Unknown error'));
      return null;
    }
  }

  Future refreshTorrents() async {
    final ts = await loadTask(connection.getTorrents());
    setState(() {
      allTorrents = ts ?? [];
      filterSortTorrents();
    });
  }

  Future apiLoadRefresh(Future action) async {
    await loadTask(action);
    // The wait is to make sure transmission has time to process our request
    await loadTask(Future.delayed(const Duration(seconds: 1)));
    await refreshTorrents();
  }

  Icon statusIcon(TorrentStatus status) {
    switch (status) {
      case TorrentStatus.stopped:
        return const Icon(Icons.pause, color: Colors.blue);
      case TorrentStatus.queuedToCheck:
        return const Icon(Icons.list);
      case TorrentStatus.checking:
        return const Icon(Icons.watch);
      case TorrentStatus.queuedToDownload:
        return const Icon(Icons.list);
      case TorrentStatus.downloading:
        return const Icon(Icons.arrow_downward, color: Colors.orange);
      case TorrentStatus.queuedToSeed:
        return const Icon(Icons.list);
      case TorrentStatus.seeding:
        return const Icon(Icons.arrow_upward, color: Colors.green);
    }
  }

  List<PopupMenuItem> torrentMenu(Torrent t) {
    return (t.status == TorrentStatus.stopped
            ? [
                PopupMenuItem(
                  child: const Text('Start'),
                  onTap: () => apiLoadRefresh(connection.startTorrent(t.id)),
                )
              ]
            : [
                PopupMenuItem(
                  child: const Text('Stop'),
                  onTap: () => apiLoadRefresh(connection.stopTorrent(t.id)),
                )
              ]) +
        (t.status == TorrentStatus.downloading || t.status == TorrentStatus.seeding
            ? [
                PopupMenuItem(
                  child: const Text('Reannounce'),
                  onTap: () => loadTask(connection.reannounceTorrent(t.id)),
                )
              ]
            : []) +
        [
          PopupMenuItem(
            child: const Text('Move'),
            onTap: () {
              // `addPostFrameCallback` is required because popup will close the dialog otherwise
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showMoveTorrentDialog(t);
              });
            },
          ),
          PopupMenuItem(
            child: const Text('Verify'),
            onTap: () => apiLoadRefresh(connection.verifyTorrent(t.id)),
          ),
          PopupMenuItem(
              child: const Text('Remove'),
              onTap: () {
                // `addPostFrameCallback` is required because popup will close the dialog otherwise
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (await confirm(context)) {
                    apiLoadRefresh(connection.removeTorrent(t.id));
                  }
                });
              }),
          PopupMenuItem(
              child: const Text('Remove & Delete data'),
              onTap: () {
                // `addPostFrameCallback` is required because popup will close the dialog otherwise
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (await confirm(context)) {
                    apiLoadRefresh(connection.removeTorrent(t.id, true));
                  }
                });
              }),
        ];
  }

  void showTorrentMenu(Torrent t) {
    final size = context.findRenderObject()?.paintBounds.size ?? Size.zero;
    final rect = RelativeRect.fromRect(tapPos & Size.zero, Offset.zero & size);
    showMenu(
      context: context,
      items: torrentMenu(t),
      position: rect,
    );
  }

  void showAddTorrentDialog() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AddTorrentDialog(
          allTorrents,
          onAddFromFile: (data, dir) {
            apiLoadRefresh(connection.addTorrentFromFile(data, dir));
          },
          onAddByUrl: (url, dir) {
            apiLoadRefresh(connection.addTorrentByUrl(url, dir));
          },
        );
      },
    );
  }

  void showMoveTorrentDialog(Torrent t) async {
    String dir = t.downloadDir;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: DownloadDirPicker(allTorrents, initialDir: dir, onChanged: (d) => dir = d),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    apiLoadRefresh(connection.moveTorrent(t.id, dir));
                  },
                  style: TextButton.styleFrom(
                    primary: Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    elevation: 3,
                    padding: const EdgeInsets.all(8),
                  ),
                  child: const Text('Move'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void filterSortTorrents() {
    setState(() {
      filteredStortedTorrents = searchController.text.isEmpty
          ? allTorrents
          : allTorrents
              .where((t) => t.name.toLowerCase().contains(searchController.text.toLowerCase()))
              .toList();
      if (sortComparer != null) {
        if (sortAscending) {
          mergeSort(
            filteredStortedTorrents,
            compare: sortComparer!,
          );
        } else {
          mergeSort(
            filteredStortedTorrents,
            compare: (Torrent a, Torrent b) => sortComparer!(b, a),
          );
        }
      }
    });
  }

  void _sort(int Function(Torrent, Torrent) comparer, int columnIndex, bool ascending) {
    sortColumnIndex = columnIndex;
    sortAscending = ascending;
    sortComparer = comparer;
    filterSortTorrents();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: loading,
      builder: ((context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Get common prefix between all directories
        final dirs = filteredStortedTorrents.map((t) => t.downloadDir);
        var commonDirPrefix = dirs.firstOrNull ?? '';
        for (final dir in dirs) {
          for (var i = 0; i < commonDirPrefix.length; i++) {
            if (dir[i] != commonDirPrefix[i]) {
              commonDirPrefix = commonDirPrefix.substring(0, i);
              break;
            }
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Expanded(flex: 0, child: Text('Torrents')),
                const SizedBox(width: 32),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: searchController,
                    decoration: InputDecoration(
                      fillColor: Colors.white,
                      filled: true,
                      labelText: 'Search',
                      suffixIcon: IconButton(
                        onPressed: () {
                          searchController.clear();
                          filterSortTorrents();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                    onEditingComplete: () => filterSortTorrents(),
                    onSaved: (_) => filterSortTorrents(),
                  ),
                ),
                const SizedBox(width: 32),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => refreshTorrents(),
              ),
            ],
          ),
          body: Listener(
            onPointerDown: (details) => tapPos = details.position,
            child: DataTable2(
              lmRatio: 2,
              smRatio: 0.4,
              columnSpacing: 20,
              scrollController: scrollController,
              sortAscending: sortAscending,
              sortColumnIndex: sortColumnIndex,
              columns: [
                DataColumn2(
                  label: const Text('Name'),
                  size: ColumnSize.L,
                  onSort: (col, asc) => _sort(
                    (a, b) => a.name.compareTo(b.name),
                    col,
                    asc,
                  ),
                ),
                DataColumn2(
                  label: const Text('Date added'),
                  size: ColumnSize.S,
                  onSort: (col, asc) => _sort(
                    (a, b) => a.addedDate.compareTo(b.addedDate),
                    col,
                    asc,
                  ),
                ),
                DataColumn2(
                  label: const Text('Size'),
                  size: ColumnSize.S,
                  numeric: true,
                  onSort: (col, asc) => _sort(
                    (a, b) => (a.size ?? 0).compareTo(b.size ?? 0),
                    col,
                    asc,
                  ),
                ),
                DataColumn2(
                  label: const Text('Up'),
                  size: ColumnSize.S,
                  numeric: true,
                  onSort: (col, asc) => _sort(
                    (a, b) => (a.upSpeed ?? 0).compareTo(b.upSpeed ?? 0),
                    col,
                    asc,
                  ),
                ),
                DataColumn2(
                  label: const Text('Down'),
                  size: ColumnSize.S,
                  numeric: true,
                  onSort: (col, asc) => _sort(
                    (a, b) => (a.downSpeed ?? 0).compareTo(b.downSpeed ?? 0),
                    col,
                    asc,
                  ),
                ),
                DataColumn2(
                  label: const Text('Dir'),
                  size: ColumnSize.M,
                  onSort: (col, asc) => _sort(
                    (a, b) => a.downloadDir.compareTo(b.downloadDir),
                    col,
                    asc,
                  ),
                ),
                DataColumn2(
                  label: const Text('Tracker'),
                  size: ColumnSize.M,
                  onSort: (col, asc) => _sort(
                    (a, b) => (a.firstTrackerHost ?? '').compareTo(b.firstTrackerHost ?? ''),
                    col,
                    asc,
                  ),
                ),
              ],
              rows: [
                for (final t in filteredStortedTorrents)
                  DataRow2(
                    cells: [
                      DataCell(Row(children: [
                        statusIcon(t.status),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t.name)),
                      ])),
                      DataCell(Text(dateString(t.addedDate), textAlign: TextAlign.center)),
                      DataCell(Text(
                        t.bytesLeft == null || t.size == null || t.bytesLeft == 0
                            ? formatOpBytes(t.size)
                            : '${formatOpBytes(t.size! - t.bytesLeft!)}/${formatOpBytes(t.size)}',
                        textAlign: TextAlign.right,
                      )),
                      DataCell(Text('${formatOpBytes(t.upSpeed)}/s', textAlign: TextAlign.right)),
                      DataCell(Text('${formatOpBytes(t.downSpeed)}/s', textAlign: TextAlign.right)),
                      DataCell(Text(t.downloadDir.substring(commonDirPrefix.length))),
                      DataCell(Text(t.firstTrackerHost ?? '')),
                    ],
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (ctx) => TorrentPage(t)));
                    },
                    onLongPress: () => showTorrentMenu(t), // TODO: multi-select
                    onSecondaryTap: () => showTorrentMenu(t),
                    onSecondaryTapDown: (details) => tapPos = details.globalPosition,
                  ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => showAddTorrentDialog(),
            child: const Icon(Icons.add),
          ),
        );
      }),
    );
  }
}

class TorrentPage extends StatelessWidget {
  final Torrent t;
  const TorrentPage(this.t, {Key? key}) : super(key: key);

  Widget propRow(String title, String? value) {
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          Expanded(child: Text(value ?? '<null>', textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // TODO: reload button
      appBar: AppBar(title: const Text('Torrent')),
      body: Listener(
        child: ListView(
          controller: AdjustableScrollController(100),
          children: [
            propRow('Name', t.name),
            propRow('Status', t.status.name),
            propRow('Date added', dateString(t.addedDate)),
            propRow(
              'Size',
              t.bytesLeft == null || t.size == null || t.bytesLeft == 0
                  ? formatOpBytes(t.size)
                  : '${formatOpBytes(t.size! - t.bytesLeft!)}/${formatOpBytes(t.size)}',
            ),
            propRow('Download speed', '${formatOpBytes(t.downSpeed)}/s'),
            propRow('Upload speed', '${formatOpBytes(t.upSpeed)}/s'),
            propRow('Total downloaded', formatOpBytes(t.downTotal)),
            propRow('Total uploaded', formatOpBytes(t.upTotal)),
            propRow('Download dir', t.downloadDir),
            propRow('Trackers', t.trackers.map((e) => e.announce).join('\n')),
            // TODO: more fields
          ],
        ),
      ),
    );
  }
}
