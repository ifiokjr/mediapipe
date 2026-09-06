import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/header.dart';
import 'package:jaspr_content/components/image.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/components/sidebar_toggle_button.dart';
import 'package:jaspr_content/components/theme_toggle.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import 'components/site_skin.dart';
import 'main.server.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);
  runApp(
    ContentApp(
      templateEngine: const MustacheTemplateEngine(),
      parsers: const [MarkdownParser()],
      extensions: [HeadingAnchorsExtension(), const TableOfContentsExtension()],
      components: [
        Callout(),
        CustomComponent(
          pattern: 'PackageGrid',
          builder: (_, _, _) => const PackageGrid(),
        ),
        const Image(zoom: true),
      ],
      layouts: [
        const DocsLayout(
          header: Header(
            title: 'MP API reference',
            logo: 'images/logo.svg',
            leading: [SidebarToggleButton(), SiteSkin()],
            items: [
              ThemeToggle(),
              a(
                href: 'https://github.com/ifiokjr/mediapipe',
                target: Target.blank,
                attributes: {'rel': 'noopener noreferrer'},
                [Component.text('GitHub ↗')],
              ),
            ],
          ),
          sidebar: Sidebar(
            groups: [
              SidebarGroup(
                links: [
                  SidebarLink(text: 'Overview', href: '.'),
                  SidebarLink(text: 'Quickstart', href: 'quickstart'),
                  SidebarLink(text: 'Platform support', href: 'platforms'),
                ],
              ),
              SidebarGroup(
                title: 'Packages',
                links: [
                  SidebarLink(text: 'mp_core', href: 'packages/core'),
                  SidebarLink(text: 'mp_camera', href: 'packages/camera'),
                  SidebarLink(text: 'mp_vision', href: 'packages/vision'),
                  SidebarLink(text: 'mp_text', href: 'packages/text'),
                  SidebarLink(text: 'mp_audio', href: 'packages/audio'),
                  SidebarLink(text: 'mp_genai', href: 'packages/genai'),
                ],
              ),
              SidebarGroup(
                title: 'Guides',
                links: [
                  SidebarLink(text: 'Models & assets', href: 'guides/models'),
                  SidebarLink(text: 'Live streams', href: 'guides/live-streams'),
                  SidebarLink(text: 'Device verification', href: 'guides/device-verification'),
                  SidebarLink(text: 'Privacy & security', href: 'guides/privacy-security'),
                  SidebarLink(text: 'Migrate from MediaPipe', href: 'guides/migration'),
                ],
              ),
              SidebarGroup(
                title: 'Project',
                links: [
                  SidebarLink(text: 'Architecture', href: 'project/architecture'),
                  SidebarLink(text: 'Releases', href: 'project/releases'),
                ],
              ),
            ],
          ),
        ),
      ],
      theme: ContentTheme(
        primary: const ThemeColor(Color('#171815'), dark: Color('#f2efe6')),
        background: const ThemeColor(Color('#f4f1e8'), dark: Color('#10110f')),
        text: const ThemeColor(Color('#373831'), dark: Color('#d9d5ca')),
        colors: [
          ContentColors.headings.apply(
            const ThemeColor(Color('#171815'), dark: Color('#f2efe6')),
          ),
          ContentColors.links.apply(
            const ThemeColor(Color('#171815'), dark: Color('#f2efe6')),
          ),
          ContentColors.quoteBorders.apply(const Color('#ff694d')),
          ContentColors.preBg.apply(const Color('#171815')),
          ContentColors.preCode.apply(const Color('#f4f1e8')),
        ],
      ),
    ),
  );
}
