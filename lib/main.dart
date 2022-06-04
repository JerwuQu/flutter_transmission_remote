import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:context_menus/context_menus.dart';
import 'package:collection/collection.dart';
import 'dart:convert';

import 'package:transmission_remote/transmission.dart';

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
  }

  Future<ConnectionInfo?> editConnection(ConnectionInfo source) async {
    ConnectionInfo conn = ConnectionInfo.copy(source);
    ConnectionInfo? returnConn;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: SizedBox(
            width: 400,
            height: 200,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'RPC URL (ends with /rpc/)'),
                    initialValue: conn.url,
                    onChanged: (str) => conn.url = str,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'Username (optional)'),
                    initialValue: conn.username,
                    onChanged: (str) => conn.username = str,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(hintText: 'Password (optional)'),
                    initialValue: conn.password,
                    onChanged: (str) => conn.password = str,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    style: TextButton.styleFrom(
                      primary: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      elevation: 3,
                      padding: const EdgeInsets.all(8),
                    ),
                    onPressed: () {
                      returnConn = conn;
                      return Navigator.of(context).pop();
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return returnConn;
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
        return ContextMenuOverlay(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Connections'),
            ),
            body: ListView(
              controller: AdjustableScrollController(100),
              children: connections
                  .mapIndexed<Widget>(
                    (index, conn) => ContextMenuRegion(
                      enableLongPress: true,
                      contextMenu: GenericContextMenu(buttonConfigs: [
                        ContextMenuButtonConfig("Edit", onPressed: () async {
                          final editedConn = await editConnection(conn);
                          if (editedConn != null) {
                            setState(() {
                              connections[index] = editedConn;
                              savePrefs();
                            });
                          }
                        }),
                        ContextMenuButtonConfig("Delete", onPressed: () {
                          setState(() => connections.remove(conn));
                        }),
                      ]),
                      child: ListTile(
                        title:
                            Text(conn.username == '' ? conn.url : '${conn.username}@${conn.url}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => ConnectionPage(conn: conn),
                            ),
                          );
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final conn = await editConnection(ConnectionInfo.empty());
                if (conn != null) {
                  setState(() {
                    connections.add(conn);
                    savePrefs();
                  });
                }
              },
              child: const Icon(Icons.add),
            ),
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
  late TransmissionConnection connection;
  late Future<List<Torrent>> torrents;

  @override
  void initState() {
    super.initState();
    ConnectionInfo ci = widget.conn;
    connection = TransmissionConnection(ci.url, ci.username, ci.password);
    torrents = connection.getTorrents();
  }

  Icon statusIcon(TorrentStatus status) {
    switch (status) {
      case TorrentStatus.stopped:
        return const Icon(Icons.stop, color: Colors.blue);
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
        return ContextMenuOverlay(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Torrents'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    setState(() {
                      torrents = connection.getTorrents();
                    });
                  },
                )
              ],
            ),
            body: ListView(
              controller: AdjustableScrollController(100),
              children: [
                for (final t in snapshot.data!)
                  ContextMenuRegion(
                    enableLongPress: true,
                    contextMenu: GenericContextMenu(buttonConfigs: [
                      // TODO: all of these
                      ContextMenuButtonConfig("Pause", onPressed: () async {}),
                      ContextMenuButtonConfig("Move", onPressed: () async {}),
                      ContextMenuButtonConfig("Check", onPressed: () async {}),
                      ContextMenuButtonConfig("Remove", onPressed: () async {}),
                      ContextMenuButtonConfig("Remove & Delete data", onPressed: () async {}),
                    ]),
                    child: ListTile(
                      title: Row(children: [
                        statusIcon(t.status),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t.name)),
                      ]),
                      onTap: () {}, // TODO
                    ),
                  ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                // TODO: add torrent
              },
              child: const Icon(Icons.add),
            ),
          ),
        );
      }),
    );
  }
}
