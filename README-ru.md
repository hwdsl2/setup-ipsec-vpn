[English](README.md) | [简体中文](README-zh.md) | [繁體中文](README-zh-Hant.md) | [日本語](README-ja.md) | [Русский](README-ru.md)

# Скрипты автоматической настройки сервера IPsec VPN

[![Статус сборки](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml/badge.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml) [![Звезды GitHub](docs/images/badges/github-stars.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Звезды Docker](docs/images/badges/docker-stars.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-ru.md) [![Загрузки Docker](docs/images/badges/docker-pulls.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-ru.md)

Разверните собственный сервер IPsec VPN всего за несколько минут с поддержкой IPsec/L2TP, Cisco IPsec и IKEv2.

IPsec VPN шифрует сетевой трафик, поэтому никто между вами и VPN-сервером не сможет перехватывать ваши данные во время их передачи через Интернет. Это особенно полезно при использовании незащищённых сетей, например в кофейнях, аэропортах или гостиничных номерах.

Мы будем использовать [Libreswan](https://libreswan.org/) в качестве сервера IPsec и [xl2tpd](https://github.com/xelerance/xl2tpd) в качестве поставщика L2TP.

**[&raquo; :book: Книга: Privacy Tools in the Age of AI](docs/vpn-book.md) &nbsp;[Build Your Own VPN Server](docs/vpn-book.md)**

## Быстрый старт

Сначала подготовьте ваш Linux-сервер\* с установленной системой Ubuntu, Debian или CentOS.

Используйте эту однострочную команду для настройки сервера IPsec VPN:

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

Данные для входа в VPN будут сгенерированы случайным образом и показаны после завершения установки.

**Дополнительно:** Установите [WireGuard](https://github.com/hwdsl2/wireguard-install/blob/master/README-ru.md) и/или [OpenVPN](https://github.com/hwdsl2/openvpn-install/blob/master/README-ru.md) на тот же сервер.

<details>
<summary>
Посмотреть работу скрипта (запись терминала).
</summary>

**Примечание:** Эта запись предназначена только для демонстрационных целей. Учетные данные VPN в этой записи **НЕ** являются действительными.

<p align="center"><img src="docs/images/script-demo.svg"></p>
</details>
<details>
<summary>
Нажмите здесь, если не удаётся скачать.
</summary>

Вы также можете использовать `curl` для загрузки:

```bash
curl -fsSL https://get.vpnsetup.net -o vpn.sh && sudo sh vpn.sh
```

Альтернативные URL для установки:

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

Если вы не можете скачать файл, откройте [vpnsetup.sh](vpnsetup.sh), затем нажмите кнопку `Raw` справа. Нажмите `Ctrl/Cmd+A`, чтобы выделить всё, `Ctrl/Cmd+C`, чтобы скопировать, затем вставьте в ваш любимый редактор.
</details>

Также доступен готовый [образ Docker](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-ru.md). Для других вариантов и настройки клиентов прочитайте разделы ниже.

\* Облачный сервер, виртуальный частный сервер (VPS) или выделенный сервер.

## Возможности

- Полностью автоматическая настройка сервера IPsec VPN, ввод пользователя не требуется
- Поддержка IKEv2 с мощными и быстрыми шифрами (например, AES-GCM)
- Генерация профилей VPN для автоматической настройки устройств iOS, macOS и Android
- Поддержка Windows, macOS, iOS, Android, Chrome OS и Linux в качестве VPN-клиентов
- Включает вспомогательные скрипты для управления пользователями VPN и сертификатами

## Требования

Облачный сервер, виртуальный частный сервер (VPS) или выделенный сервер с установленной системой:

- Ubuntu 24.04 или 22.04
- Debian 13, 12 или 11
- CentOS Stream 10 или 9
- Rocky Linux или AlmaLinux
- Oracle Linux
- Amazon Linux 2

<details>
<summary>
Другие поддерживаемые дистрибутивы Linux.
</summary>

- Raspberry Pi OS (Raspbian)
- Kali Linux
- Alpine Linux
- Red Hat Enterprise Linux (RHEL)
</details>

Это также включает виртуальные машины Linux в публичных облаках, таких как [DigitalOcean](https://blog.ls20.com/digitalocean), [Vultr](https://blog.ls20.com/vultr), [Linode](https://blog.ls20.com/linode), [OVH](https://www.ovhcloud.com/en/vps/) и [Microsoft Azure](https://azure.microsoft.com). Пользователи публичных облаков также могут выполнить развёртывание с помощью [пользовательскими данными](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup).

Быстрое развёртывание в:

[![Deploy to Linode](docs/images/linode-deploy-button.png)](https://cloud.linode.com/stackscripts/37239) &nbsp;[![Deploy to AWS](docs/images/aws-deploy-button.png)](aws/README.md) &nbsp;[![Deploy to Azure](docs/images/azure-deploy-button.png)](azure/README.md)

[**&raquo; Я хочу запустить собственный VPN, но у меня нет сервера для этого**](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps)

Для серверов с внешним файрволом (например, [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)) откройте UDP-порты 500 и 4500 для VPN.

Также доступен готовый [образ Docker](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-ru.md). Продвинутые пользователи могут установить его на [Raspberry Pi](https://www.raspberrypi.com). [[1]](https://elasticbyte.net/posts/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/) [[2]](https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/)

:warning: **НЕ** запускайте эти скрипты на вашем ПК или Mac! Их следует использовать только на сервере!

## Установка

Сначала обновите ваш сервер с помощью `sudo apt-get update && sudo apt-get dist-upgrade` (Ubuntu/Debian) или `sudo yum update`, затем перезагрузите систему. Это необязательно, но рекомендуется.

Чтобы установить VPN, выберите один из следующих вариантов:

**Вариант 1:** Позвольте скрипту сгенерировать случайные учетные данные VPN (они будут показаны после завершения).

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

**Вариант 2:** Отредактируйте скрипт и укажите собственные учетные данные VPN.

```bash
wget https://get.vpnsetup.net -O vpn.sh
nano -w vpn.sh
[Замените на собственные значения: YOUR_IPSEC_PSK, YOUR_USERNAME и YOUR_PASSWORD]
sudo sh vpn.sh
```

**Примечание:** Безопасный IPsec PSK должен состоять как минимум из 20 случайных символов.

**Вариант 3:** Определите учетные данные VPN как переменные окружения.

```bash
# Все значения ДОЛЖНЫ быть заключены в 'одинарные кавычки'
# НЕ используйте внутри значений следующие специальные символы: \ " '
wget https://get.vpnsetup.net -O vpn.sh
sudo VPN_IPSEC_PSK='your_ipsec_pre_shared_key' \
VPN_USER='your_vpn_username' \
VPN_PASSWORD='your_vpn_password' \
sh vpn.sh
```

При желании вы можете установить [WireGuard](https://github.com/hwdsl2/wireguard-install/blob/master/README-ru.md) и/или [OpenVPN](https://github.com/hwdsl2/openvpn-install/blob/master/README-ru.md) на том же сервере. Если ваш сервер работает на CentOS Stream, Rocky Linux или AlmaLinux, сначала установите OpenVPN/WireGuard, а затем установите IPsec VPN.

<details>
<summary>
Нажмите здесь, если не удаётся скачать.
</summary>

Вы также можете использовать `curl` для загрузки. Например:

```bash
curl -fL https://get.vpnsetup.net -o vpn.sh
sudo sh vpn.sh
```

Альтернативные URL для установки:

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

Если вы не можете скачать файл, откройте [vpnsetup.sh](vpnsetup.sh), затем нажмите кнопку `Raw` справа. Нажмите `Ctrl/Cmd+A`, чтобы выделить всё, `Ctrl/Cmd+C`, чтобы скопировать, затем вставьте в ваш любимый редактор.
</details>
<details>
<summary>
Я хочу установить более старую версию Libreswan 4.
</summary>

Обычно рекомендуется использовать последнюю версию [Libreswan](https://libreswan.org/) 5, которая является версией по умолчанию в этом проекте. Однако если вы хотите установить более старую версию Libreswan 4:

```bash
wget https://get.vpnsetup.net -O vpn.sh
sudo VPN_SWAN_VER=4.15 sh vpn.sh
```

**Примечание:** Если версия Libreswan 5 уже установлена, возможно, вам сначала потребуется [удалить VPN](docs/uninstall.md), прежде чем устанавливать Libreswan версии 4. В качестве альтернативы можно скачать [скрипт обновления](#обновление-libreswan), отредактировать его, указав `SWAN_VER=4.15`, затем запустить скрипт.
</details>

## Настройка параметров VPN

### Использование альтернативных DNS-серверов

По умолчанию клиенты настроены использовать [Google Public DNS](https://developers.google.com/speed/public-dns/) при активном VPN. При установке VPN вы можете при желании указать собственные DNS-серверы для всех режимов VPN. Пример:

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
```

Используйте `VPN_DNS_SRV1` для указания основного DNS-сервера и `VPN_DNS_SRV2` для указания резервного DNS-сервера (необязательно).

Ниже приведён список некоторых популярных публичных DNS-провайдеров для справки.

| Провайдер | Основной DNS | Резервный DNS | Примечания |
| -------- | ----------- | ------------- | ----- |
| [Google Public DNS](https://developers.google.com/speed/public-dns) | 8.8.8.8 | 8.8.4.4 | Используется по умолчанию в этом проекте |
| [Cloudflare](https://1.1.1.1/dns/) | 1.1.1.1 | 1.0.0.1 | См. также: [Cloudflare for families](https://1.1.1.1/family/) |
| [Quad9](https://www.quad9.net) | 9.9.9.9 | 149.112.112.112 | Блокирует вредоносные домены |
| [OpenDNS](https://www.opendns.com/home-internet-security/) | 208.67.222.222 | 208.67.220.220 | Блокирует фишинговые домены, настраиваемый |
| [CleanBrowsing](https://cleanbrowsing.org/filters/) | 185.228.168.9 | 185.228.169.9 | Доступны [фильтры доменов](https://cleanbrowsing.org/filters/) |
| [NextDNS](https://nextdns.io/?from=bg25bwmp) | Различается | Различается | Блокировка рекламы, доступен бесплатный тариф. [Подробнее](https://nextdns.io/?from=bg25bwmp). |
| [Control D](https://controld.com/free-dns) | Различается | Различается | Блокировка рекламы, настраиваемый. [Подробнее](https://controld.com/free-dns). |

Если вам нужно изменить DNS-серверы после настройки VPN, см. раздел [Расширенное использование](docs/advanced-usage.md).

**Примечание:** Если IKEv2 уже настроен на сервере, переменные выше не влияют на режим IKEv2. В этом случае для настройки параметров IKEv2, таких как DNS-серверы, вы можете сначала [удалить IKEv2](docs/ikev2-howto.md#remove-ikev2), а затем снова настроить его с помощью `sudo ikev2.sh`.

### Настройка параметров IKEv2

При установке VPN продвинутые пользователи могут при желании настроить параметры IKEv2.

<details open>
<summary>
Вариант 1: Пропустить IKEv2 во время настройки VPN, затем настроить IKEv2 с пользовательскими параметрами.
</summary>

При установке VPN вы можете пропустить IKEv2 и установить только режимы IPsec/L2TP и IPsec/XAuth («Cisco IPsec»):

```bash
sudo VPN_SKIP_IKEV2=yes sh vpn.sh
```

(Необязательно) Если вы хотите указать пользовательские DNS-серверы для клиентов VPN, определите `VPN_DNS_SRV1` и при необходимости `VPN_DNS_SRV2`. Подробности смотрите в разделе [Использование альтернативных DNS-серверов](#использование-альтернативных-dns-серверов).

После этого запустите вспомогательный скрипт IKEv2, чтобы настроить IKEv2 в интерактивном режиме с пользовательскими параметрами:

```bash
sudo ikev2.sh
```

Вы можете настроить следующие параметры: DNS-имя VPN-сервера, имя и срок действия первого клиента, DNS-сервер для VPN-клиентов и необходимость защиты файлов конфигурации клиента паролем.

**Примечание:** Переменная `VPN_SKIP_IKEV2` не действует, если IKEv2 уже настроен на сервере. В этом случае для настройки параметров IKEv2 вы можете сначала [удалить IKEv2](docs/ikev2-howto.md#remove-ikev2), а затем снова настроить его с помощью `sudo ikev2.sh`.
</details>
<details>
<summary>
Вариант 2: Настройка параметров IKEv2 с помощью переменных окружения.
</summary>

При установке VPN вы можете при желании указать DNS-имя для адреса сервера IKEv2. DNS-имя должно быть полным доменным именем (FQDN). Пример:

```bash
sudo VPN_DNS_NAME='vpn.example.com' sh vpn.sh
```

Аналогично вы можете указать имя для первого клиента IKEv2. По умолчанию используется `vpnclient`, если имя не указано.

```bash
sudo VPN_CLIENT_NAME='your_client_name' sh vpn.sh
```

По умолчанию клиенты используют [Google Public DNS](https://developers.google.com/speed/public-dns/) при активном VPN. Вы можете указать собственные DNS-серверы для всех режимов VPN. Пример:

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
```

По умолчанию пароль не требуется при импорте конфигурации клиента IKEv2. Вы можете защитить файлы конфигурации клиента случайным паролем.

```bash
sudo VPN_PROTECT_CONFIG=yes sh vpn.sh
```
</details>
<details>
<summary>
Для справки: список параметров IKEv1 и IKEv2.
</summary>

| Параметр IKEv1\*            | Значение по умолчанию | Настройка (переменная окружения)\*\* |
| --------------------------- | --------------------- | ------------------------------------ |
| Адрес сервера (DNS-имя)     | -                     | Нет, но можно подключаться по DNS-имени |
| Адрес сервера (публичный IP)| Автоопределение       | VPN_PUBLIC_IP                        |
| Предварительно общий ключ IPsec | Автоматическая генерация | VPN_IPSEC_PSK                    |
| Имя пользователя VPN        | vpnuser               | VPN_USER                             |
| Пароль VPN                  | Автоматическая генерация | VPN_PASSWORD                     |
| DNS-серверы для клиентов    | Google Public DNS     | VPN_DNS_SRV1, VPN_DNS_SRV2           |
| Пропустить настройку IKEv2  | no                    | VPN_SKIP_IKEV2=yes                   |

\* Эти параметры IKEv1 используются для режимов IPsec/L2TP и IPsec/XAuth («Cisco IPsec»).  
\*\* Определяются как переменные окружения при запуске vpn(setup).sh.

| Параметр IKEv2\*            | Значение по умолчанию | Настройка (переменная окружения)\*\* | Настройка (интерактивно)\*\*\* |
| --------------------------- | --------------------- | ------------------------------------ | ------------------------------- |
| Адрес сервера (DNS-имя)     | -                     | VPN_DNS_NAME                         | ✅                              |
| Адрес сервера (публичный IP)| Автоопределение       | VPN_PUBLIC_IP                        | ✅                              |
| Имя первого клиента         | vpnclient             | VPN_CLIENT_NAME                      | ✅                              |
| DNS-серверы для клиентов    | Google Public DNS     | VPN_DNS_SRV1, VPN_DNS_SRV2           | ✅                              |
| Защита файлов конфигурации клиента | no            | VPN_PROTECT_CONFIG=yes               | ✅                              |
| Включить/отключить MOBIKE   | Включено, если поддерживается | ❌                             | ✅                              |
| Срок действия сертификата клиента | 10 лет (120 месяцев) | VPN_CLIENT_VALIDITY\*\*\*\*     | ✅                              |
| Срок действия сертификатов CA и сервера | 10 лет (120 месяцев) | ❌                         | ❌                              |
| Имя сертификата CA          | IKEv2 VPN CA          | ❌                                   | ❌                              |
| Размер ключа сертификата    | 3072 бита             | ❌                                   | ❌                              |

\* Эти параметры IKEv2 используются для режима IKEv2.  
\*\* Определяются как переменные окружения при запуске vpn(setup).sh или при автоматической настройке IKEv2 (`sudo ikev2.sh --auto`).  
\*\*\* Можно настроить во время интерактивной настройки IKEv2 (`sudo ikev2.sh`). См. вариант 1 выше.  
\*\*\*\* Используйте `VPN_CLIENT_VALIDITY`, чтобы указать срок действия сертификата клиента в месяцах. Значение должно быть целым числом от 1 до 120.

Помимо этих параметров, продвинутые пользователи также могут [настроить подсети VPN](docs/advanced-usage.md#customize-vpn-subnets) во время настройки VPN.
</details>

## Следующие шаги

*Прочитать на других языках: [English](README.md#next-steps), [简体中文](README-zh.md#下一步), [繁體中文](README-zh-Hant.md#下一步), [日本語](README-ja.md#次のステップ), [Русский](README-ru.md#следующие-шаги).*

Настройте ваш компьютер или устройство для использования VPN. Пожалуйста, обратитесь к следующим инструкциям (на английском языке):

**[Настройка клиентов IKEv2 VPN (рекомендуется)](docs/ikev2-howto.md)**

**[Настройка клиентов IPsec/L2TP VPN](docs/clients.md)**

**[Настройка клиентов IPsec/XAuth («Cisco IPsec»)](docs/clients-xauth.md)**

**Прочитайте [:book: книгу о VPN](docs/vpn-book.md), чтобы получить доступ к [дополнительному контенту](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J).**

Наслаждайтесь собственным VPN! :sparkles::tada::rocket::sparkles:

## Важные замечания

**Пользователи Windows**: для режима IPsec/L2TP требуется [одноразовое изменение реестра](docs/clients.md#windows-error-809), если VPN-сервер или клиент находится за NAT (например, домашним роутером).

Одна и та же учетная запись VPN может использоваться на нескольких ваших устройствах. Однако из-за ограничения IPsec/L2TP, если вы хотите подключить несколько устройств из-за одного NAT (например, домашнего роутера), необходимо использовать режим [IKEv2](docs/ikev2-howto.md) или [IPsec/XAuth](docs/clients-xauth.md). Чтобы просмотреть или изменить учетные записи пользователей VPN, см. [Управление пользователями VPN](docs/manage-users.md).

Для серверов с внешним файрволом (например, [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)) откройте UDP-порты 500 и 4500 для VPN. Пользователям Aliyun см. [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433).

Клиенты настроены использовать [Google Public DNS](https://developers.google.com/speed/public-dns/) при активном VPN. Если вы предпочитаете другого DNS-провайдера, см. [Расширенное использование](docs/advanced-usage.md).

Использование поддержки ядра может повысить производительность IPsec/L2TP. Она доступна на [всех поддерживаемых ОС](#требования). Пользователям Ubuntu следует установить пакет `linux-modules-extra-$(uname -r)` и выполнить `service xl2tpd restart`.

Скрипты создадут резервные копии существующих файлов конфигурации перед внесением изменений, с суффиксом `.old-date-time`.

## Обновление Libreswan

Используйте эту однострочную команду для обновления [Libreswan](https://libreswan.org) ([список изменений](https://github.com/libreswan/libreswan/blob/main/CHANGES) | [объявления](https://lists.libreswan.org)) на вашем VPN-сервере.

```bash
wget https://get.vpnsetup.net/upg -O vpnup.sh && sudo sh vpnup.sh
```

<details>
<summary>
Нажмите здесь, если не удаётся скачать.
</summary>

Вы также можете использовать `curl` для загрузки:

```bash
curl -fsSL https://get.vpnsetup.net/upg -o vpnup.sh && sudo sh vpnup.sh
```

Альтернативные URL для обновления:

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnupgrade.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnupgrade.sh
```

Если вы не можете скачать файл, откройте [vpnupgrade.sh](extras/vpnupgrade.sh), затем нажмите кнопку `Raw` справа. Нажмите `Ctrl/Cmd+A`, чтобы выделить всё, `Ctrl/Cmd+C`, чтобы скопировать, затем вставьте в ваш любимый редактор.
</details>

Последняя поддерживаемая версия Libreswan — `5.3`. Проверить установленную версию: `ipsec --version`.

**Примечание:** `xl2tpd` можно обновить с помощью менеджера пакетов вашей системы, например `apt-get` в Ubuntu/Debian.

## Управление пользователями VPN

См. [Управление пользователями VPN](docs/manage-users.md) (на английском языке).

- [Управление пользователями VPN с помощью вспомогательных скриптов](docs/manage-users.md#manage-vpn-users-using-helper-scripts)
- [Просмотр пользователей VPN](docs/manage-users.md#view-vpn-users)
- [Просмотр или обновление IPsec PSK](docs/manage-users.md#view-or-update-the-ipsec-psk)
- [Ручное управление пользователями VPN](docs/manage-users.md#manually-manage-vpn-users)

## Расширенное использование

См. [Расширенное использование](docs/advanced-usage.md) (на английском языке).

- [Использование альтернативных DNS-серверов](docs/advanced-usage.md#use-alternative-dns-servers)
- [Изменения DNS-имени и IP-адреса сервера](docs/advanced-usage.md#dns-name-and-server-ip-changes)
- [VPN только с IKEv2](docs/advanced-usage.md#ikev2-only-vpn)
- [Внутренние IP-адреса VPN и трафик](docs/advanced-usage.md#internal-vpn-ips-and-traffic)
- [Указание публичного IP-адреса VPN-сервера](docs/advanced-usage.md#specify-vpn-servers-public-ip)
- [Настройка подсетей VPN](docs/advanced-usage.md#customize-vpn-subnets)
- [Переадресация портов клиентам VPN](docs/advanced-usage.md#port-forwarding-to-vpn-clients)
- [Раздельная маршрутизация (Split tunneling)](docs/advanced-usage.md#split-tunneling)
- [Доступ к подсети VPN-сервера](docs/advanced-usage.md#access-vpn-servers-subnet)
- [Доступ к клиентам VPN из подсети сервера](docs/advanced-usage.md#access-vpn-clients-from-servers-subnet)
- [Изменение правил IPTables](docs/advanced-usage.md#modify-iptables-rules)
- [Развёртывание алгоритма управления перегрузкой Google BBR](docs/advanced-usage.md#deploy-google-bbr-congestion-control)

## Удаление VPN

Чтобы удалить IPsec VPN, запустите [вспомогательный скрипт](extras/vpnuninstall.sh):

**Предупреждение:** Этот вспомогательный скрипт удалит IPsec VPN с вашего сервера. Вся конфигурация VPN будет **безвозвратно удалена**, а Libreswan и xl2tpd будут удалены. Это **нельзя отменить**!

```bash
wget https://get.vpnsetup.net/unst -O unst.sh && sudo bash unst.sh
```

<details>
<summary>
Нажмите здесь, если не удаётся скачать.
</summary>

Вы также можете использовать `curl` для загрузки:

```bash
curl -fsSL https://get.vpnsetup.net/unst -o unst.sh && sudo bash unst.sh
```

Альтернативные URL скрипта:

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnuninstall.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnuninstall.sh
```
</details>

Для получения дополнительной информации см. [Удаление VPN](docs/uninstall.md).

## Обратная связь и вопросы

- Есть предложение по улучшению этого проекта? Создайте [Предложить улучшение](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose). [Pull request](https://github.com/hwdsl2/setup-ipsec-vpn/pulls) также приветствуются.
- Если вы нашли воспроизводимую ошибку, создайте отчёт об ошибке для [IPsec VPN](https://github.com/libreswan/libreswan/issues?q=is%3Aissue) или для [скрипты VPN](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose).
- Есть вопрос? Пожалуйста, сначала выполните поиск по [существующим issues](https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue) и комментариям [в этом Gist](https://gist.github.com/hwdsl2/9030462#comments) и [в моём блоге](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread).
- Задавайте вопросы, связанные с VPN, в списках рассылки [Libreswan](https://lists.libreswan.org) или [strongSwan](https://lists.strongswan.org), либо прочитайте эти вики: [[1]](https://libreswan.org/wiki/Main_Page) [[2]](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks) [[3]](https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation) [[4]](https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server) [[5]](https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup).

## Лицензия

Copyright (C) 2014-2025 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   
Основано на [работе Thomas Sarlandie](https://github.com/sarfata/voodooprivacy) (Copyright 2012)

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
Эта работа распространяется по лицензии [Creative Commons Attribution-ShareAlike 3.0 Unported License](http://creativecommons.org/licenses/by-sa/3.0/)  
Требуется указание авторства: пожалуйста, указывайте моё имя в любых производных работах и сообщайте мне, как вы её улучшили!
