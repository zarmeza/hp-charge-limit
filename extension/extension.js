'use strict';

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import UPower from 'gi://UPowerGlib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

const RETRY_INTERVAL_MS = 100;
const MAX_RETRIES = 100;

// GNOME Shell 50 already has the icon we want:
//
//   battery-level-N-plugged-in-symbolic
//
// but its PowerToggle only uses it when UPower reports
// ChargeThresholdEnabled. That flag requires a kernel-level charge threshold,
// which this HP laptop does not expose. Our limit lives in the EC via HP WMI,
// so UPower correctly reports pending-charge but leaves the flag false.
//
// This extension patches the live PowerToggle so pending-charge + AC online
// uses the plugged-in icon and says so in quick settings.

export default class HpChargeLimitIndicator extends Extension {
    enable() {
        this._powerToggle = null;
        this._origSync = null;
        this._patchedSync = null;
        this._origSubtitle = null;
        this._origAccessibleName = null;
        this._lastPaused = null;
        this._retryId = 0;
        this._retries = 0;

        this._upowerClient = UPower.Client.new_full(null);
        this._linePowerDevices = this._upowerClient.get_devices()
            .filter(device => device.kind === UPower.DeviceKind.LINE_POWER);

        this._linePowerHandlers = this._linePowerDevices.map(device =>
            device.connect('notify::online', () => this._powerToggle?._sync()));

        this._retryId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT,
            RETRY_INTERVAL_MS,
            () => this._tryPatch());
    }

    _tryPatch() {
        const powerToggle =
            Main.panel?.statusArea?.quickSettings?._system?._systemItem?._powerToggle;

        if (!powerToggle) {
            if (++this._retries >= MAX_RETRIES) {
                this._retryId = 0;
                console.warn('hp-charge-limit: power toggle not found; desktop indicator inactive');
                return GLib.SOURCE_REMOVE;
            }
            return GLib.SOURCE_CONTINUE;
        }

        this._retryId = 0;
        this._powerToggle = powerToggle;
        this._origSync = powerToggle._sync;
        this._origSubtitle = powerToggle.subtitle;
        this._origAccessibleName = powerToggle.accessible_name;

        this._patchedSync = () => this._syncPowerToggle();
        powerToggle._sync = this._patchedSync;
        powerToggle._sync();

        console.log('hp-charge-limit: desktop indicator active');
        return GLib.SOURCE_REMOVE;
    }

    _isAcOnline() {
        return this._linePowerDevices.some(device => device.online);
    }

    _syncPowerToggle() {
        const powerToggle = this._powerToggle;
        if (!powerToggle)
            return;

        this._origSync.call(powerToggle);

        const proxy = powerToggle._proxy;
        const paused =
            proxy &&
            proxy.State === UPower.DeviceState.PENDING_CHARGE &&
            Number.isFinite(proxy.Percentage) &&
            this._isAcOnline();

        if (!paused) {
            this._setPaused(false);
            return;
        }

        const fill = 10 * Math.floor(proxy.Percentage / 10);
        const percentage = Math.round(proxy.Percentage);
        const gicon = new Gio.ThemedIcon({
            name: `battery-level-${fill}-plugged-in-symbolic`,
            use_default_fallbacks: false,
        });

        powerToggle.set({
            gicon,
            fallback_icon_name: `battery-level-${fill}-symbolic`,
            subtitle: _('Plugged in · charging paused'),
            accessible_name: _('Battery {percentage}%, plugged in, charging paused')
                .replace('{percentage}', `${percentage}`),
        });

        this._setPaused(true, percentage);
    }

    _setPaused(paused, percentage = null) {
        if (this._lastPaused === paused)
            return;

        this._lastPaused = paused;

        if (paused) {
            console.log(`hp-charge-limit: charging paused at ${percentage}%`);
            return;
        }

        // PowerToggle does not own the subtitle/accessible name in GNOME 50,
        // so put back whatever was there before the paused state.
        const powerToggle = this._powerToggle;
        if (powerToggle) {
            powerToggle.subtitle = this._origSubtitle;
            powerToggle.accessible_name = this._origAccessibleName;
        }
        console.log('hp-charge-limit: charging state normal');
    }

    disable() {
        if (this._retryId) {
            GLib.source_remove(this._retryId);
            this._retryId = 0;
        }

        if (this._linePowerHandlers) {
            this._linePowerDevices.forEach((device, index) => {
                const handlerId = this._linePowerHandlers[index];
                if (handlerId)
                    device.disconnect(handlerId);
            });
            this._linePowerHandlers = [];
        }
        this._linePowerDevices = [];

        const powerToggle = this._powerToggle;
        if (powerToggle) {
            if (powerToggle._sync === this._patchedSync)
                powerToggle._sync = this._origSync;

            powerToggle.subtitle = this._origSubtitle;
            powerToggle.accessible_name = this._origAccessibleName;

            try {
                powerToggle._sync();
            } catch (e) {
                console.error(`hp-charge-limit: failed to restore indicator: ${e.message}`);
            }
        }

        this._powerToggle = null;
        this._origSync = null;
        this._patchedSync = null;
        this._origSubtitle = null;
        this._origAccessibleName = null;
        this._lastPaused = null;
        this._upowerClient = null;
    }
}
