- name: Create HTTP directory tree
  file:
    path: "{{ item }}"
    state: directory
    owner: caddy
    group: caddy
    mode: '0755'
  loop:
    - "{{ http_file_root }}"
    - "{{ http_file_root }}{{ installer_subpath }}"
    - "{{ user_data_base }}"

- name: Deploy PXE menu
  template:
    src: menu.ipxe.j2
    dest: "{{ http_file_root }}/menu.ipxe"
    owner: caddy
    group: caddy
    mode: '0644'

- name: Download installer assets
  get_url:
    url: "{{ debian_mirror }}{{ installer_subpath }}/{{ item }}"
    dest: "{{ http_file_root }}{{ installer_subpath }}/{{ item }}"
    mode: '0644'
  loop:
    - linux
    - initrd.gz
  register: fetched_assets

- name: Fail if downloads unsuccessful
  fail:
    msg: 'Failed to download installer assets'
  when: fetched_assets.results | selectattr('status_code', '!=', 200) | list | length > 0

- name: Deploy cloud-init user-data for each PVE host
  template:
    src: ../templates/user-data.j2
    dest: "{{ http_file_root }}/user-data/{{ item }}-user-data.yml"
    owner: caddy
    group: caddy
    mode: '0755'
  loop: "{{ groups['pve'] }}"
