import 'dart:convert';
import 'dart:io';

/// Validates every link in the built documentation site.
///
/// The site is a static Jaspr build that serves each content page at a real
/// route under a deployment base path. Every page sets `<base href="<base>/">`,
/// so a browser resolves *relative* links against the site root rather than
/// against the current page. That makes a link mistake a silent 404 that no
/// compiler catches, so this check enforces the contract:
///
/// - a relative link resolves against the base path and must reach a built page
///   or a real static asset,
/// - a root-absolute link must stay inside the deployment base path, because
///   `](/foo)` would drop `/mediapipe/`,
/// - navigation between pages must target the page, not a fragment on it, so
///   crawlers and the sidebar's active-route highlighting see a real route,
/// - every built content page must be reachable from the rendered site.
///
/// Run after `docs:build`, which writes the static site to `docs/build/jaspr`.
void main(List<String> arguments) {
  final Directory root = Directory.current;
  final Directory output = Directory('${root.path}/docs/build/jaspr');
  final Directory content = Directory('${root.path}/docs/content');

  if (!output.existsSync()) {
    stderr.writeln('No built site at ${output.path}. Run `docs:build` first.');
    exit(1);
  }

  final String basePath = _basePath(root);
  final Set<String> routes = _builtRoutes(output);
  final Set<String> assets = _builtAssets(output);
  final Set<String> contentRoutes = _contentRoutes(content);

  final List<String> failures = <String>[];
  final Set<String> linkedRoutes = <String>{};

  for (final File file in output.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.html')) continue;
    final String pageRoute = _routeFor(file, output);
    final String html = file.readAsStringSync();

    if (!html.contains('<base href="$basePath"')) {
      failures.add(
        '/$pageRoute: missing <base href="$basePath">, so relative links resolve wrongly.',
      );
    }

    for (final RegExpMatch match in RegExp(r'href="([^"]+)"').allMatches(html)) {
      final String href = match.group(1)!;
      if (href.startsWith('http://') ||
          href.startsWith('https://') ||
          href.startsWith('mailto:') ||
          href.startsWith('data:')) {
        continue;
      }
      // A bare fragment stays on the current page. The table of contents and
      // heading anchors use this form, and it is the only correct way to
      // navigate within a page.
      if (href.startsWith('#')) continue;

      final String path = href.split('#').first;
      final bool hasFragment = href.contains('#');
      final bool isAbsolute = path.startsWith('/');

      if (isAbsolute && !_withinBase(path, basePath)) {
        failures.add('/$pageRoute: "$href" is root-absolute and escapes $basePath.');
        continue;
      }

      final String target = isAbsolute
          ? _routeFromPath(path.substring(basePath.length))
          : _resolveAgainstBase(path);

      if (assets.contains(target)) continue;

      if (!routes.contains(target)) {
        failures.add('/$pageRoute: "$href" resolves to /$target, which was not built.');
        continue;
      }
      linkedRoutes.add(target);

      // Crossing pages should land on the page, not on a section of it. A route
      // plus fragment still resolves correctly in a browser, but it hides the
      // destination from a crawler and defeats active-route highlighting.
      if (hasFragment && target != pageRoute) {
        failures.add('/$pageRoute: "$href" crosses to a fragment on another page; link the page.');
      }
    }
  }

  for (final String route in contentRoutes) {
    if (route == '' || linkedRoutes.contains(route)) continue;
    failures.add('/$route was built but no rendered page links to it.');
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'docs links are consistent: ${routes.length} routes, '
      '${assets.length} assets, base path $basePath.',
    );
    return;
  }

  stderr.writeln('docs link check failed:');
  for (final String failure in failures) {
    stderr.writeln('  - $failure');
  }
  exitCode = 1;
}

/// Reads the deployment base path from the same data the build and the mdt
/// providers use, so the three cannot drift.
String _basePath(Directory root) {
  final File file = File('${root.path}/docs/data/links.json');
  if (!file.existsSync()) return '/';
  final Object? decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?> || decoded['docs'] is! String) return '/';
  final String path = Uri.parse(decoded['docs']! as String).path;
  if (path.isEmpty || path == '/') return '/';
  return path.endsWith('/') ? path : '$path/';
}

/// Whether an absolute path sits inside the deployment base path.
bool _withinBase(String path, String basePath) =>
    basePath == '/' || path == basePath || path.startsWith(basePath);

/// Normalizes a route fragment, dropping any `index.html` suffix.
String _routeFromPath(String path) {
  var route = path;
  while (route.startsWith('/')) {
    route = route.substring(1);
  }
  while (route.endsWith('/')) {
    route = route.substring(0, route.length - 1);
  }
  if (route == 'index.html') return '';
  if (route.endsWith('/index.html')) {
    return route.substring(0, route.length - '/index.html'.length);
  }
  return route;
}

/// Resolves a relative link the way a browser does when `<base href>` is set:
/// against the base path, not against the current page.
String _resolveAgainstBase(String href) {
  final List<String> segments = <String>[];
  for (final String part in href.split('/')) {
    switch (part) {
      case '' || '.':
        continue;
      case '..':
        if (segments.isNotEmpty) segments.removeLast();
      default:
        segments.add(part);
    }
  }
  return segments.join('/');
}

Set<String> _builtRoutes(Directory output) {
  final Set<String> routes = <String>{};
  for (final File file in output.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.html')) continue;
    routes.add(_routeFor(file, output));
  }
  return routes;
}

/// Static files that a page may link directly (favicons, images, robots.txt).
Set<String> _builtAssets(Directory output) {
  final Set<String> assets = <String>{};
  for (final File file in output.listSync(recursive: true).whereType<File>()) {
    if (file.path.endsWith('.html')) continue;
    assets.add(_routeFor(file, output));
  }
  return assets;
}

String _routeFor(File file, Directory output) {
  final String relative = file.path.substring(output.path.length + 1);
  if (relative == 'index.html') return '';
  if (relative.endsWith('/index.html')) {
    return relative.substring(0, relative.length - '/index.html'.length);
  }
  return relative;
}

/// The routes the content directory should produce, so a page that silently
/// fails to render is still reported.
Set<String> _contentRoutes(Directory content) {
  final Set<String> routes = <String>{};
  for (final File file in content.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.md')) continue;
    final String relative = file.path.substring(content.path.length + 1);
    if (relative.startsWith('_')) continue;
    final String withoutExtension = relative.substring(0, relative.length - 3);
    if (withoutExtension == 'index') {
      routes.add('');
    } else if (withoutExtension.endsWith('/index')) {
      routes.add(withoutExtension.substring(0, withoutExtension.length - '/index'.length));
    } else {
      routes.add(withoutExtension);
    }
  }
  return routes;
}
