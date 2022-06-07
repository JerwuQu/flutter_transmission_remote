import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:collection/collection.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:file_picker/file_picker.dart';

import 'transmission.dart';

void main() {
  runApp(const MyApp());
}

Future showError(BuildContext context, String title, String message) async {
  await showDialog(
    context: context,
    builder: (builder) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
      );
    },
  );
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

// from: https://stackoverflow.com/a/71427895
class AdjustableScrollController extends ScrollController {
  AdjustableScrollController([int extraScrollSpeed = 40]) {
    super.addListener(() {
      ScrollDirection scrollDirection = super.position.userScrollDirection;
      if (scrollDirection != ScrollDirection.idle) {
        double scrollEnd = super.offset +
            (scrollDirection == ScrollDirection.reverse ? extraScrollSpeed : -extraScrollSpeed);
        scrollEnd =
            min(super.position.maxScrollExtent, max(super.position.minScrollExtent, scrollEnd));
        jumpTo(scrollEnd);
      }
    });
  }
}

Future<bool> youSure(BuildContext context, [String title = 'Are you sure?']) async {
  bool response = false;
  await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
                child: const Text('Yes'),
                onPressed: () {
                  response = true;
                  Navigator.of(context).pop();
                }),
            TextButton(
                child: const Text('No'),
                onPressed: () {
                  response = false;
                  Navigator.of(context).pop();
                }),
          ],
        );
      });
  return response;
}

String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  final int i = (log(bytes) / log(1024)).floor();
  return '${(bytes * 100 / pow(1024, i)).round() / 100} ${['B', 'KB', 'MB', 'GB', 'TB'][i]}';
}

String formatOpBytes(int? bytes) => bytes == null ? '?' : formatBytes(bytes);

class ConnectionInfo {
  String url, username, password;

  ConnectionInfo.empty()
      : url = '',
        username = '',
        password = '';
  ConnectionInfo.copy(ConnectionInfo source)
      : url = source.url,
        username = source.username,
        password = source.password;

  ConnectionInfo.fromJson(Map<String, dynamic> json)
      : url = json['url'],
        username = json['username'],
        password = json['password'];
  toJson() => {
        'url': url,
        'username': username,
        'password': password,
      };
}

class ConnectionListPage extends StatefulWidget {
  const ConnectionListPage({Key? key}) : super(key: key);

  @override
  State<ConnectionListPage> createState() => ConnectionListPageState();
}

class ConnectionListPageState extends State<ConnectionListPage> {
  late List<ConnectionInfo> connections;
  late Future _loadPrefs;

  ConnectionListPageState() : super() {
    _loadPrefs = loadPrefs();
  }

  Future loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = jsonDecode(prefs.getString('connections') ?? '[]');
    connections =
        connectionsJson.map<ConnectionInfo>((json) => ConnectionInfo.fromJson(json)).toList();
  }

  Future savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = jsonEncode(connections.map((c) => c.toJson()).toList());
    await prefs.setString('connections', connectionsJson);
    // TODO: support storing connections encrypted
  }

  Future editConnection([int? index]) async {
    ConnectionInfo conn =
        index == null ? ConnectionInfo.empty() : ConnectionInfo.copy(connections[index]);
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
                                  connections.add(conn);
                                } else {
                                  connections[index] = conn;
                                }
                                savePrefs();
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
                                    if (await youSure(context)) {
                                      setState(() {
                                        connections.removeAt(index);
                                        savePrefs();
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
    return FutureBuilder(
      future: _loadPrefs,
      builder: ((context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Connections'),
          ),
          body: ListView(
            controller: AdjustableScrollController(100),
            children: connections
                .mapIndexed<Widget>(
                  (index, conn) => ListTile(
                    title: Text(conn.username == '' ? conn.url : '${conn.username}@${conn.url}'),
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
      }),
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
  List<Torrent> torrents = [];
  Future<void> loading = Future.value();

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
      torrents = ts ?? [];
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
              onTap: () async {
                if (await youSure(context)) {
                  apiLoadRefresh(connection.removeTorrent(t.id));
                }
              }),
          PopupMenuItem(
              child: const Text('Remove & Delete data'),
              onTap: () async {
                if (await youSure(context)) {
                  apiLoadRefresh(connection.removeTorrent(t.id, true));
                }
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
          torrents,
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
                  child: DownloadDirPicker(torrents, initialDir: dir, onChanged: (d) => dir = d),
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

  int? _sortColumnIndex;
  bool _sortAscending = true;
  void _sort<T extends Comparable<T>>(
    T Function(Torrent) getField,
    int columnIndex,
    bool ascending,
  ) {
    setState(() {
      if (ascending) {
        mergeSort(torrents, compare: (Torrent a, Torrent b) => getField(a).compareTo(getField(b)));
      } else {
        mergeSort(torrents, compare: (Torrent a, Torrent b) => getField(b).compareTo(getField(a)));
      }
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  String dateString(int secs) {
    final iso = DateTime.fromMillisecondsSinceEpoch(secs * 1000).toLocal().toIso8601String();
    return iso.substring(0, iso.indexOf('.')).replaceFirst('T', '\n');
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Torrents'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => refreshTorrents(),
              )
            ],
          ),
          body: DataTable2(
            lmRatio: 2,
            smRatio: 0.4,
            columnSpacing: 5,
            scrollController: AdjustableScrollController(100), // TODO: keep offset after refresh
            sortAscending: _sortAscending,
            sortColumnIndex: _sortColumnIndex,
            columns: [
              DataColumn2(
                label: const Text('Name'),
                size: ColumnSize.L,
                onSort: (col, asc) => _sort((t) => t.name, col, asc),
              ),
              DataColumn2(
                label: const Text('Date Added'),
                size: ColumnSize.S,
                onSort: (col, asc) => _sort<num>((t) => t.addedDate, col, asc),
              ),
              DataColumn2(
                label: const Text('Size'),
                size: ColumnSize.S,
                numeric: true,
                onSort: (col, asc) => _sort<num>((t) => t.size ?? 0, col, asc),
              ),
              DataColumn2(
                label: const Text('Up'),
                size: ColumnSize.S,
                numeric: true,
                onSort: (col, asc) => _sort<num>((t) => t.upSpeed ?? 0, col, asc),
              ),
              DataColumn2(
                label: const Text('Down'),
                size: ColumnSize.S,
                numeric: true,
                onSort: (col, asc) => _sort<num>((t) => t.downSpeed ?? 0, col, asc),
              ),
            ],
            rows: [
              for (final t in torrents)
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
                  ],
                  onTap: () {},
                  onSecondaryTapDown: (details) => tapPos = details.globalPosition,
                  // TODO: add onTapDown to data_table_2 and use onTap instead of onSecondaryTap
                  onSecondaryTap: () => showTorrentMenu(t),
                ),
            ],
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
