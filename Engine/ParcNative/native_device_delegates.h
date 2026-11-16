// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_DEVICE_DELEGATES_H_
#define PARC_NATIVE_NATIVE_DEVICE_DELEGATES_H_

#include <memory>

#include "content/public/browser/bluetooth_delegate.h"
#include "content/public/browser/hid_delegate.h"
#include "content/public/browser/serial_delegate.h"
#include "content/public/browser/usb_delegate.h"

namespace parc {
std::unique_ptr<content::BluetoothDelegate> CreateNativeBluetoothDelegate();
std::unique_ptr<content::UsbDelegate> CreateNativeUsbDelegate();
std::unique_ptr<content::HidDelegate> CreateNativeHidDelegate();
std::unique_ptr<content::SerialDelegate> CreateNativeSerialDelegate();
}

#endif
