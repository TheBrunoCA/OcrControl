#Requires AutoHotkey v2.0

#Include RapidOcr\RapidOcr.ahk
#Include Screenshooter.ahk

MAX_TRIES_LIMIT := 10 ; Define a constant for the maximum tries limit

/**
 * @description Performs OCR on a specific control within a window.
 * @param {string} control The control identifier to capture and analyze.
 * @param {string} win_title The title of the window containing the control. Defaults to 'A'.
 * @param {string} win_text Optional text to further identify the window.
 * @param {function} modifier_callback A function to modify the result of the OCR. Called before verifier_callback.
 * @param {function} verifier_callback A function to validate the OCR result. Should return true if valid.
 * @param {number} max_tries Maximum number of attempts to perform OCR. Defaults to 3.
 * @param {number} default_margin The default margin to add to the control's position for each retry. Defaults to 0.
 * @param {number} margin_per_try The margin to add to the control's position for each retry. Defaults to 0.
 * @param {boolean} debug Boolean flag to enable debugging. Defaults to false.
 * @returns {string} The OCR result as a string if successful.
 * @throws Throws an error if OCR fails after max_tries or if critical issues occur.
 */
OcrControl(control, win_title := '', win_text := '', modifier_callback := '', verifier_callback := '', max_tries := 3, default_margin := 0, margin_per_try := 0, debug := false, log_callback := false) {
    ; Validate the control parameter
    if log_callback is Func{
        if log_callback.MinParams < 1 {
            throw TypeError('Invalid number of parameters for log_callback, expected at least 1')
        }
    } else {
        log_callback := false
    }

    if control == '' {
        if debug {
            MsgBox("Error: Control parameter is missing.")
        }
        if log_callback {
            log_callback.Call("Error: Control parameter is missing.")
        }
        throw Error("Control parameter is missing. Please specify a valid control to proceed.")
    }

    ; Limit the maximum number of retries to the defined constant
    if max_tries > MAX_TRIES_LIMIT {
        if debug {
            MsgBox("Warning: max_tries exceeds limit. Adjusting to " MAX_TRIES_LIMIT)
        }
        if log_callback {
            log_callback.Call("Warning: max_tries exceeds limit. Adjusting to " MAX_TRIES_LIMIT)
        }
        max_tries := MAX_TRIES_LIMIT
    }

    try {
        ; Initialize OCR parameters
        ocr_params := RapidOcr.OcrParam()
        ocr_params.doAngle := false
        ocr_params.mostAngle := false


        ; If debugging is enabled, specify the output path for OCR debugging
        if debug {
            ocr_params.outputPath := A_ScriptDir '\ocr_control.png'
            MsgBox("Debug mode enabled. Output path set to: " ocr_params.outputPath)
        }

        ; Define the temporary path to save the control screenshot
        printscreen_path := A_Temp '\control.bmp'
        if debug {
            printscreen_path := A_ScriptDir '\control.bmp'
            MsgBox("Printscreen path set to: " printscreen_path)
        }

        ; Attempt OCR up to the specified number of tries
        ocr := RapidOcr()
        loop max_tries {
            if debug {
                MsgBox("Attempt " A_Index " of " max_tries)
            }
            if log_callback {
                log_callback.Call("Attempt " A_Index " of " max_tries)
            }

            try {
                ; Capture a screenshot of the specified control
                if debug {
                    MsgBox("Capturing screenshot for control: " control)
                }
                if log_callback {
                    log_callback.Call("Capturing screenshot for control: " control)
                }
                Screenshooter.CaptureControl(WinGetID(win_title), control, printscreen_path, (margin_per_try * A_Index) + default_margin)
            } catch Error as e {
                ; Handle errors in capturing the screenshot
                if debug {
                    MsgBox("Error during screenshot capture: " e.Message)
                }
                if log_callback {
                    log_callback.Call("Error during screenshot capture: " e.Message)
                }
                throw Error("Failed to capture screenshot for control: " control " - " e.Message)
            }

            ; Perform OCR on the captured screenshot
            if debug {
                MsgBox("Performing OCR on captured screenshot.")
            }
            if log_callback {
                log_callback.Call("Performing OCR on captured screenshot.")
            }
            try {
                ocr_result := ocr.ocr_from_file(printscreen_path, ocr_params)
            } catch Error as e {
                if debug {
                    MsgBox("Error during OCR: " e.Message)
                }
                if log_callback {
                    log_callback.Call("Error during OCR: " e.Message)
                }
                throw Error("Error during OCR: " e.Message)
            }

            if debug {
                asw := MsgBox('Want to see the OCR result?', 'OCR Result', 0x1020)
                if asw == 'Yes' {
                    RunWait(printscreen_path)
                }
            }

            ; If a modifier callback is provided and valid, use it to modify the OCR result
            if modifier_callback != '' and IsValidFunction(modifier_callback) {
                if debug {
                    MsgBox("Using modifier callback to modify OCR result. Value before modifier: " ocr_result)
                }
                if log_callback {
                    log_callback.Call("Using modifier callback to modify OCR result. Value before modifier: " ocr_result)
                }
                ocr_result := modifier_callback(ocr_result)
                
                if debug {
                    MsgBox("Value after modifier: " ocr_result)
                }
                if log_callback {
                    log_callback.Call("Value after modifier: " ocr_result)
                }
            }

            ; Log the OCR result
            if debug {
                MsgBox("OCR Result: " (ocr_result ? ocr_result : "<empty>"))
            }
            if log_callback {
                log_callback.Call("OCR Result: " (ocr_result ? ocr_result : "<empty>"))
            }

            ; Check if a verifier callback function is provided and valid
            if verifier_callback != '' and IsValidFunction(verifier_callback) {
                if debug {
                    MsgBox("Using verifier callback to validate OCR result.")
                }
                if log_callback {
                    log_callback.Call("Using verifier callback to validate OCR result.")
                }
                if verifier_callback(ocr_result) {
                    if debug {
                        MsgBox("OCR result validated successfully.")
                    }
                    if log_callback {
                        log_callback.Call("OCR result validated successfully.")
                    }
                    return ocr_result ; Return the result if validation is successful
                }
                if debug {
                    MsgBox("OCR result validation failed. Retrying...")
                }
                if log_callback {
                    log_callback.Call("OCR result validation failed. Retrying...")
                }
                continue ; Retry if validation fails
            }

            return ocr_result ; Return the OCR result if no callback is provided
        }

        ; Throw an error if all retries fail
        if debug {
            MsgBox("Error: Failed to validate OCR result after " max_tries " tries.")
        }
        if log_callback {
            log_callback.Call("Error: Failed to validate OCR result after " max_tries " tries.")
        }
        throw Error("Failed to validate OCR result after " max_tries " tries. Last OCR result: " (ocr_result ?
            ocr_result : "<none>"))
    }
    catch Error as e {
        ; Catch and rethrow any errors encountered during the process
        if debug {
            MsgBox("Critical Error: " e.Message)
        }
        if log_callback {
            log_callback.Call("Critical Error: " e.Message)
        }
        throw Error("Error in OCR control: " e.Message)
    }
}

; Utility function to check if a given callback is a valid function
IsValidFunction(callback) {
    return Type(callback) == 'Func' || Type(callback) == 'BoundFunc'
}
