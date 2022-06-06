import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:collection/collection.dart';
import 'package:data_table_2/data_table_2.dart';
import 'dart:convert';

import 'transmission.dart';

void main() {
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

class ConnectionPage extends StatefulWidget {
  final ConnectionInfo conn;
  const ConnectionPage({required this.conn, Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => ConnectionPageState();
}

class ConnectionPageState extends State<ConnectionPage> {
  Offset tapPos = Offset.zero;

  late TransmissionConnection connection;
  late Future<List<Torrent>> torrents;

  @override
  void initState() {
    super.initState();
    ConnectionInfo ci = widget.conn;
    connection = TransmissionConnection(ci.url, ci.username, ci.password);
    torrents = connection.getTorrents();
  }

  void refreshTorrents([bool wait = false]) {
    setState(() {
      // The wait is to make sure Transmission has a time to process our change before we request the new list
      torrents = wait
          ? Future.delayed(const Duration(seconds: 1)).then((value) => connection.getTorrents())
          : connection.getTorrents();
    });
  }

  Icon statusIcon(TorrentStatus status) {
    switch (status) {
      case TorrentStatus.stopped:
        return const Icon(Icons.pause, color: Colors.blue);
      case TorrentStatus.queuedToCheck:
        return const Icon(Icons.queue); // TODO
      case TorrentStatus.checking:
        return const Icon(Icons.watch);
      case TorrentStatus.queuedToDownload:
        return const Icon(Icons.queue); // TODO
      case TorrentStatus.downloading:
        return const Icon(Icons.arrow_downward, color: Colors.orange);
      case TorrentStatus.queuedToSeed:
        return const Icon(Icons.queue); // TODO
      case TorrentStatus.seeding:
        return const Icon(Icons.arrow_upward, color: Colors.green);
    }
  }

  List<PopupMenuItem> torrentMenu(Torrent t) {
    return (t.status == TorrentStatus.stopped
            ? [
                PopupMenuItem(
                  child: const Text('Start'),
                  onTap: () async {
                    await connection.startTorrent(t.id);
                    refreshTorrents(true);
                  },
                )
              ]
            : [
                PopupMenuItem(
                  child: const Text('Stop'),
                  onTap: () async {
                    await connection.stopTorrent(t.id);
                    refreshTorrents(true);
                  },
                )
              ]) +
        (t.status == TorrentStatus.downloading || t.status == TorrentStatus.seeding
            ? [
                PopupMenuItem(
                  child: const Text('Reannounce'),
                  onTap: () async {
                    await connection.reannounceTorrent(t.id);
                  },
                )
              ]
            : []) +
        [
          PopupMenuItem(
              child: const Text('Move'),
              onTap: () async {
                // TODO
              }),
          PopupMenuItem(
              child: const Text('Verify'),
              onTap: () async {
                await connection.verifyTorrent(t.id);
                refreshTorrents(true);
              }),
          PopupMenuItem(
              child: const Text('Remove'),
              onTap: () async {
                if (await youSure(context)) {
                  await connection.removeTorrent(t.id);
                  refreshTorrents(true);
                }
              }),
          PopupMenuItem(
              child: const Text('Remove & Delete data'),
              onTap: () async {
                if (await youSure(context)) {
                  await connection.removeTorrent(t.id, true);
                  refreshTorrents(true);
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

  void addTorrentDialog() async {
    final torrentList = await torrents;
    String torrentUrl = '';
    String downloadDir = torrentList.firstOrNull?.downloadDir ?? '';
    final downloadDirController = TextEditingController(text: downloadDir);
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(
                    hintText: 'https://...',
                    labelText: 'Torrent URL',
                  ),
                  onChanged: (str) => torrentUrl = str,
                ),
                Row(
                  children: [
                    PopupMenuButton(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
                      tooltip: 'Choose from current torrents',
                      itemBuilder: (BuildContext context) {
                        return torrentList
                            .map((t) => t.downloadDir)
                            .toSet()
                            .map((d) => PopupMenuItem(value: d, child: Text(d)))
                            .toList();
                      },
                      onSelected: (str) {
                        downloadDir = str as String;
                        downloadDirController.text = downloadDir;
                      },
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: downloadDirController,
                        decoration: const InputDecoration(
                          hintText: '~/Download',
                          labelText: 'Download directory',
                        ),
                        onChanged: (str) => downloadDir = str,
                      ),
                    ),
                  ],
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
                    Navigator.of(context).pop();
                    await connection.addTorrentByUrl(torrentUrl, downloadDir);
                    refreshTorrents(true);
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Torrent>>(
      future: torrents,
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
            scrollController: AdjustableScrollController(100),
            columns: const [
              DataColumn2(label: Text('Name'), size: ColumnSize.L),
              DataColumn2(label: Text('Size'), size: ColumnSize.S, numeric: true),
              DataColumn2(label: Text('Up/Down'), size: ColumnSize.S),
            ],
            rows: [
              for (final t in snapshot.data!)
                DataRow2(
                  cells: [
                    DataCell(Row(children: [
                      statusIcon(t.status),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t.name)),
                    ])),
                    DataCell(Text(t.bytesLeft == null || t.size == null || t.bytesLeft == 0
                        ? formatOpBytes(t.size)
                        : '${formatOpBytes(t.size! - t.bytesLeft!)}/${formatOpBytes(t.size)}')),
                    DataCell(
                        Text('${formatOpBytes(t.upSpeed)}/s / ${formatOpBytes(t.downSpeed)}/s')),
                  ],
                  onTap: () {},
                  onSecondaryTapDown: (details) => tapPos = details.globalPosition,
                  // TODO: add onTapDown to data_table_2 and use onTap instead of onSecondaryTap
                  onSecondaryTap: () => showTorrentMenu(t),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              addTorrentDialog();
            },
            child: const Icon(Icons.add),
          ),
        );
      }),
    );
  }
}
