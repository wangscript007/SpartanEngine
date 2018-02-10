/*
Copyright(c) 2016-2017 Panos Karabelas

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions :

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

//= INCLUDES =================
#include "DInput.h"
#include <sstream>
#include "../../Logging/Log.h"
#include "../../Core/Engine.h"
//============================

//= NAMESPACES ================
using namespace Directus::Math;
using namespace std;
//=============================

namespace Directus
{
	DInput::DInput()
	{
		m_directInput	= nullptr;
		m_keyboard		= nullptr;
		m_mouse			= nullptr;
	}

	DInput::~DInput()
	{
		// Release the mouse.
		if (m_mouse)
		{
			m_mouse->Unacquire();
			m_mouse->Release();
			m_mouse = nullptr;
		}

		// Release the keyboard.
		if (m_keyboard)
		{
			m_keyboard->Unacquire();
			m_keyboard->Release();
			m_keyboard = nullptr;
		}

		// Release the main interface to direct input.
		if (m_directInput)
		{
			m_directInput->Release();
			m_directInput = nullptr;
		}
	}

	bool DInput::Initialize()
	{
		if (!Engine::GetWindowHandle() || !Engine::GetWindowInstance())
			return false;

		auto windowHandle = (HWND)Engine::GetWindowHandle();
		auto windowInstance = (HINSTANCE)Engine::GetWindowInstance();

		// Make sure the window has focus, otherwise the mouse and keyboard won't be able to be aquired.
		SetForegroundWindow(windowHandle);

		// Initialize the main direct input interface.
		HRESULT result = DirectInput8Create(windowInstance, DIRECTINPUT_VERSION, IID_IDirectInput8, (void**)&m_directInput, nullptr);
		if (FAILED(result))
		{
			switch (result)
			{
				case DIERR_INVALIDPARAM:			LOG_ERROR("DInput: DirectInput8Create() Failed, invalid parameters.");		break;
				case DIERR_BETADIRECTINPUTVERSION:	LOG_ERROR("DInput: DirectInput8Create() Failed, beta direct input version."); break;
				case DIERR_OLDDIRECTINPUTVERSION:	LOG_ERROR("DInput: DirectInput8Create() Failed, old direct input version.");	break;
				case DIERR_OUTOFMEMORY:				LOG_ERROR("DInput: DirectInput8Create() Failed, out of memory.");				break;
				default:							LOG_ERROR("DInput: Failed to initialize the DirectInput interface.");
			}
			return false;
		}

		// Initialize the direct input interface for the keyboard.
		result = m_directInput->CreateDevice(GUID_SysKeyboard, &m_keyboard, nullptr);
		if (FAILED(result))
		{
			LOG_ERROR("DInput: Failed to initialize a DirectInput keyboard.");
			return false;
		}

		// Set the data format. In this case since it is a keyboard we can use the predefined data format.
		result = m_keyboard->SetDataFormat(&c_dfDIKeyboard);
		if (FAILED(result))
		{
			LOG_ERROR("DInput: Failed to initialize DirectInput keyboard data format.");
		}

		// Set the cooperative level of the keyboard to share with other programs.
		result = m_keyboard->SetCooperativeLevel(windowHandle, DISCL_FOREGROUND | DISCL_NONEXCLUSIVE);
		if (FAILED(result))
		{
			LOG_ERROR("DInput: Failed to set DirectInput keyboard's cooperative level.");
		}

		// Acquire the keyboard.
		if (!GetKeyboard())
		{
			LOG_ERROR("DInput: Failed to aquire the keyboard.");
		}

		// Initialize the direct input interface for the mouse.
		result = m_directInput->CreateDevice(GUID_SysMouse, &m_mouse, nullptr);
		if (FAILED(result))
		{
			LOG_ERROR("DInput: Failed to set DirectInput keyboard's cooperative level.");
			return false;
		}

		// Set the data format for the mouse using the pre-defined mouse data format.
		result = m_mouse->SetDataFormat(&c_dfDIMouse);
		if (FAILED(result))
		{
			LOG_ERROR("DInput: Failed to initialize a DirectInput mouse.");
		}

		// Set the cooperative level of the mouse to share with other programs.
		result = m_mouse->SetCooperativeLevel(windowHandle, DISCL_FOREGROUND | DISCL_NONEXCLUSIVE);
		if (FAILED(result))
		{
			LOG_ERROR("DInput: Failed to set DirectInput mouse's cooperative level.");
		}

		// Acquire the mouse.
		if (!GetMouse())
		{
			LOG_ERROR("DInput: Failed to aquire the mouse.");
		}

		stringstream ss;
		ss << hex << DIRECTINPUT_VERSION;
		string major = ss.str().erase(1, 2);
		string minor = ss.str().erase(0, 1);
		LOG_INFO("Input: DirectInput " + major + "." + minor);

		return true;
	}

	void DInput::Update()
	{
		ReadKeyboard();
		ReadMouse();
	}

	bool DInput::IsKeyboardKeyDown(int key)
	{
		// hex: 0x80 | Bin: 10000000
		return m_keyboardState[key] & 0x80;
	}

	bool DInput::IsMouseKeyDown(int key)
	{
		//  0	= Left Button
		//  1	= Right Button
		//  3	= Middle Button (Scroll Wheel pressed)
		//  4-7 = Side buttons
		return m_mouseState.rgbButtons[key] & 0x80;
	}

	Vector3 DInput::GetMouseDelta()
	{
		// lX = position x delta
		// lY = position y delta
		// lZ = wheel delta
		return Vector3((float)m_mouseState.lX, (float)m_mouseState.lY, (float)m_mouseState.lZ);
	}

	bool DInput::GetKeyboard()
	{
		return SUCCEEDED(m_keyboard->Acquire());
	}

	bool DInput::GetMouse()
	{
		return SUCCEEDED(m_mouse->Acquire());
	}

	bool DInput::ReadKeyboard()
	{
		// Read keyboard
		HRESULT result = m_keyboard->GetDeviceState(sizeof(m_keyboardState), static_cast<LPVOID>(&m_keyboardState));
		if (SUCCEEDED(result))
			return true;

		// If the keyboard lost focus or was not acquired then try to get control back.
		if ((result == DIERR_INPUTLOST) || (result == DIERR_NOTACQUIRED))
		{
			GetKeyboard();
		}
		return false;
	}

	bool DInput::ReadMouse()
	{
		// Read mouse
		HRESULT result = m_mouse->GetDeviceState(sizeof(DIMOUSESTATE), static_cast<LPVOID>(&m_mouseState));
		if (SUCCEEDED(result))
			return true;

		// If the mouse lost focus or was not acquired then try to get control back.
		if ((result == DIERR_INPUTLOST) || (result == DIERR_NOTACQUIRED))
		{
			GetMouse();
		}
		return false;
	}
}