// The Soup Auth details Jellyfin shows in its catalog and plugin list.
export const plugin = {
  guid: 'c8a7e6d5-4b3a-2918-07f6-e5d4c3b2a190',
  name: 'Soup Auth',
  owner: 'soup',
  category: 'Authentication',
  overview: 'Soup entitlement mailbox: invite by Google email and exchange Soup assertions for Jellyfin sessions.',
  description:
    'Outbound-only Jellyfin plugin for Soup identity. Admins invite/revoke from Dashboard → Soup Invites; ' +
    'connection settings under Plugins → Soup Auth. Clients exchange Soup JWTs at POST /SoupAuth/Exchange.',
};
