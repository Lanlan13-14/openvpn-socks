#!/usr/bin/env python3
import json
import os
import sys


def env(name, default=''):
    return os.environ.get(name, default)


def truthy(value):
    return str(value).strip().lower() in {'1', 'true', 'yes', 'on'}


def maybe_int(value, default):
    if value in (None, ''):
        return default
    return int(value)


def dns_server_defaults(server_type):
    server_type = server_type.lower()
    if server_type in {'https', 'h3', 'tls', 'quic'}:
        return 443 if server_type in {'https', 'h3'} else 853
    return 53


def build_tls(prefix):
    cfg = {}
    server_name = env(f'{prefix}_TLS_SERVER_NAME')
    if server_name:
        cfg['server_name'] = server_name
    insecure = env(f'{prefix}_TLS_INSECURE')
    if prefix == 'PROXY' and not insecure:
        insecure = env('PROXY_SKIP_CERT_VERIFY')
    if truthy(insecure):
        cfg['insecure'] = True
    alpn = env(f'{prefix}_TLS_ALPN')
    if alpn:
        cfg['alpn'] = [x.strip() for x in alpn.split(',') if x.strip()]
    return cfg




def split_csv(value):
    return [x.strip() for x in value.split(',') if x.strip()]


def parse_json_object(value, name):
    if not value:
        return {}
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        raise SystemExit(f'invalid JSON in {name}: {exc}')
    if not isinstance(parsed, dict):
        raise SystemExit(f'{name} must be a JSON object')
    return parsed


def build_vless_tls():
    if not truthy(env('PROXY_TLS_ENABLED', '1')):
        return None
    tls = {'enabled': True}
    tls.update(build_tls('PROXY'))
    if not tls.get('server_name'):
        tls['server_name'] = env('PROXY_HOST')
    utls_fingerprint = env('PROXY_UTLS_FINGERPRINT')
    if truthy(env('PROXY_UTLS_ENABLED')):
        tls['utls'] = {
            'enabled': True,
            'fingerprint': utls_fingerprint or 'chrome',
        }
    reality_public_key = env('PROXY_REALITY_PUBLIC_KEY')
    reality_short_id = env('PROXY_REALITY_SHORT_ID')
    if reality_public_key or reality_short_id or truthy(env('PROXY_REALITY_ENABLED')):
        if not reality_public_key:
            raise SystemExit('missing PROXY_REALITY_PUBLIC_KEY for vless reality')
        tls['reality'] = {
            'enabled': True,
            'public_key': reality_public_key,
        }
        if reality_short_id:
            tls['reality']['short_id'] = reality_short_id
    return tls


def build_vless_transport():
    transport_type = env('PROXY_TRANSPORT', '').strip().lower()
    if not transport_type:
        return None
    if transport_type not in {'ws', 'websocket'}:
        raise SystemExit(f'unsupported PROXY_TRANSPORT for vless: {transport_type}')
    transport = {
        'type': 'ws',
        'path': env('PROXY_WS_PATH', env('PROXY_TRANSPORT_PATH', '/')),
    }
    headers = parse_json_object(env('PROXY_WS_HEADERS', env('PROXY_TRANSPORT_HEADERS')), 'PROXY_WS_HEADERS')
    ws_host = env('PROXY_WS_HOST', env('PROXY_TRANSPORT_HOST'))
    if ws_host:
        headers.setdefault('Host', ws_host)
    if headers:
        transport['headers'] = headers
    max_early_data = env('PROXY_WS_MAX_EARLY_DATA')
    if max_early_data:
        transport['max_early_data'] = maybe_int(max_early_data, 0)
    early_header = env('PROXY_WS_EARLY_DATA_HEADER_NAME')
    if early_header:
        transport['early_data_header_name'] = early_header
    return transport

def build_dns_server():
    server_type = env('DNS_SERVER_TYPE', 'https').strip().lower() or 'https'
    server = {
        'type': server_type,
        'tag': 'remote',
        'server': env('DNS_SERVER', '1.1.1.1'),
        'server_port': maybe_int(env('DNS_SERVER_PORT'), dns_server_defaults(server_type)),
        'detour': env('DNS_DETOUR', 'proxy'),
    }
    if server_type in {'tls', 'quic', 'https', 'h3'}:
        tls = build_tls('DNS')
        if tls:
            server['tls'] = tls
    if server_type in {'https', 'h3'}:
        server['path'] = env('DNS_PATH', '/dns-query')
    return server


def build_proxy_outbound():
    proxy_type = env('PROXY_TYPE', 'socks').strip().lower() or 'socks'
    host = env('PROXY_HOST')
    port = maybe_int(env('PROXY_PORT'), 0)
    if not host or not port:
        raise SystemExit('missing PROXY_HOST or PROXY_PORT')

    if proxy_type == 'socks':
        outbound = {
            'type': 'socks',
            'tag': 'proxy',
            'server': host,
            'server_port': port,
        }
        if env('PROXY_UDP_OVER_TCP', env('PROXY_UOT', env('PROXY_UDP', ''))).strip():
            outbound['udp_over_tcp'] = {
                'enabled': truthy(env('PROXY_UDP_OVER_TCP', env('PROXY_UOT', env('PROXY_UDP', 'true')))),
                'version': maybe_int(env('PROXY_UOT_VERSION'), 2),
            }
        user = env('PROXY_USER')
        password = env('PROXY_PASS')
        if user:
            outbound['username'] = user
        if password:
            outbound['password'] = password
        return outbound

    if proxy_type == 'anytls':
        password = env('PROXY_PASSWORD', env('PROXY_PASS'))
        if not password:
            raise SystemExit('missing PROXY_PASSWORD for anytls outbound')
        outbound = {
            'type': 'anytls',
            'tag': 'proxy',
            'server': host,
            'server_port': port,
            'password': password,
        }
        tls = {'enabled': True}
        tls.update(build_tls('PROXY'))
        if not tls.get('server_name'):
            tls['server_name'] = host
        outbound['tls'] = tls
        return outbound

    if proxy_type in {'shadowsocks', 'ss', 'ss2022'}:
        method = env('PROXY_METHOD', '2022-blake3-aes-128-gcm')
        password = env('PROXY_PASSWORD', env('PROXY_PASS'))
        if not password:
            raise SystemExit('missing PROXY_PASSWORD for shadowsocks outbound')
        outbound = {
            'type': 'shadowsocks',
            'tag': 'proxy',
            'server': host,
            'server_port': port,
            'method': method,
            'password': password,
        }
        if env('PROXY_UDP_OVER_TCP', env('PROXY_UOT', env('PROXY_UDP', ''))).strip():
            outbound['udp_over_tcp'] = {
                'enabled': truthy(env('PROXY_UDP_OVER_TCP', env('PROXY_UOT', env('PROXY_UDP', 'true')))),
                'version': maybe_int(env('PROXY_UOT_VERSION'), 2),
            }
        plugin = env('PROXY_PLUGIN')
        if plugin:
            outbound['plugin'] = plugin
        plugin_opts = env('PROXY_PLUGIN_OPTS')
        if plugin_opts:
            outbound['plugin_opts'] = plugin_opts
        network = env('PROXY_NETWORK')
        if network:
            outbound['network'] = split_csv(network)
        return outbound

    if proxy_type == 'vless':
        uuid = env('PROXY_UUID')
        if not uuid:
            raise SystemExit('missing PROXY_UUID for vless outbound')
        outbound = {
            'type': 'vless',
            'tag': 'proxy',
            'server': host,
            'server_port': port,
            'uuid': uuid,
        }
        flow = env('PROXY_FLOW')
        if flow:
            outbound['flow'] = flow
        network = env('PROXY_NETWORK')
        if network:
            outbound['network'] = split_csv(network)
        packet_encoding = env('PROXY_PACKET_ENCODING')
        if packet_encoding:
            outbound['packet_encoding'] = packet_encoding
        tls = build_vless_tls()
        if tls:
            outbound['tls'] = tls
        transport = build_vless_transport()
        if transport:
            outbound['transport'] = transport
        return outbound

    raise SystemExit(f'unsupported PROXY_TYPE: {proxy_type}')


def build_config():
    tun_address = [env('SING_TUN_ADDRESS', '172.19.0.1/30')]
    if truthy(env('IPV6_ENABLED')):
        tun_address.append(env('SING_TUN_ADDRESS6', 'fd42:42:42:43::1/126'))

    return {
        'log': {'level': env('SING_BOX_LOG_LEVEL', 'warning')},
        'dns': {
            'servers': [build_dns_server()],
            'rules': [
                {
                    'action': 'route',
                    'server': 'remote',
                    'strategy': env('DNS_STRATEGY', 'prefer_ipv4'),
                }
            ],
            'final': 'remote',
        },
        'inbounds': [
            {
                'type': 'tun',
                'tag': 'tun-in',
                'interface_name': env('SING_TUN_NAME', 'sb-tun0'),
                'address': tun_address,
                'mtu': maybe_int(env('SING_TUN_MTU'), 9000),
                'auto_route': False,
                'strict_route': False,
                'stack': env('SING_TUN_STACK', 'mixed'),
                'sniff': False,
            }
        ],
        'outbounds': [
            {'type': 'direct', 'tag': 'direct'},
            build_proxy_outbound(),
        ],
        'route': {
            'rules': [
                {
                    'ip_cidr': [f"{env('SING_TUN_DNS_ADDRESS', '172.19.0.2')}/32"],
                    'port': 53,
                    'action': 'hijack-dns',
                },
                {
                    'protocol': 'dns',
                    'action': 'hijack-dns',
                },
            ],
            'final': 'proxy',
            'auto_detect_interface': True,
        },
    }


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '/etc/sing-box/config.json'
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(build_config(), f, ensure_ascii=False, indent=2)
        f.write('\n')


if __name__ == '__main__':
    main()
