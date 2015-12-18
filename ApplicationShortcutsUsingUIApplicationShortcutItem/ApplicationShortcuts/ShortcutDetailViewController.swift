/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    The detail view controller for viewing and editing shortcut information (localized title, localized subtitle, and icon)
*/

import UIKit

class ShortcutDetailViewController: UITableViewController {
    // MARK: Properties
    
    @IBOutlet weak var titleTextField: UITextField!
    @IBOutlet weak var subtitleTextField: UITextField!
    @IBOutlet weak var pickerView: UIPickerView!
    @IBOutlet weak var doneButton: UIBarButtonItem!
    
    var pickerItems = ["Compose", "Play", "Pause", "Add", "Location", "Search", "Share"]
    
    /// Used to share information between this controller and its parent.
    var shortcutItem: UIApplicationShortcutItem?
    
    /// The observer token for the `UITextFieldDidChangeNotification`.
    var textFieldObserverToken: NSObjectProtocol?
    
    // MARK: Object Life Cycle
    
    deinit {
        guard let token = textFieldObserverToken else { return }
        NSNotificationCenter.defaultCenter().removeObserver(token)
    }
    
    // MARK: View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize the UI to reflect the values of the `shortcutItem`.
        guard let selectedShortcutItem = shortcutItem else {
            fatalError("The `selectedShortcutItem` was not set.")
        }
        
        title = selectedShortcutItem.localizedTitle
        
        titleTextField.text = selectedShortcutItem.localizedTitle
        subtitleTextField.text = selectedShortcutItem.localizedSubtitle
            
        // Extract the raw value representing the icon from the userInfo dictionary, if provided.
        guard let iconRawValue = selectedShortcutItem.userInfo?[AppDelegate.applicationShortcutUserInfoIconKey] as? Int else { return }
        
        // Select the matching row in the picker for the icon type.
        let iconType = iconTypeForSelectedRow(iconRawValue)
        
        // The `iconType` returned may not align to the `iconRawValue` so use the `iconType`'s `rawValue`.
        pickerView.selectRow(iconType.rawValue, inComponent:0, animated:false)
        
        let notificationCenter = NSNotificationCenter.defaultCenter()
        textFieldObserverToken = notificationCenter.addObserverForName(UITextFieldTextDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let strongSelf = self else { return }

            // You cannot dismiss the view controller without a valid shortcut title.
            let titleTextLength = strongSelf.titleTextField.text?.characters.count ?? 0
            strongSelf.doneButton.enabled = titleTextLength > 0
        }
    }
    
    // MARK: UITextFieldDelegate
    
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        textField.resignFirstResponder()

        return true
    }
    
    // MARK: UIPickerViewDataSource
    
    func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return pickerItems.count
    }
    
    func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return pickerItems[row]
    }

    /// Constructs a UIApplicationShortcutIconType based on the integer result from our picker.
    func iconTypeForSelectedRow(row: Int) -> UIApplicationShortcutIconType {
        return UIApplicationShortcutIconType(rawValue: row) ?? .Compose
    }
    
    // MARK: UIStoryboardSegue Handling
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        guard let selectedShortcutItem = shortcutItem else {
            fatalError("The `selectedShortcutItem` was not set.")
        }
           
        if segue.identifier == "ShortcutDetailUpdated" {
            // In the updated case, create a shortcut item to represent the final state of the view controller.
            let iconType = iconTypeForSelectedRow(pickerView.selectedRowInComponent(0))
            
            let icon = UIApplicationShortcutIcon(type: iconType)
            
            shortcutItem = UIApplicationShortcutItem(type: selectedShortcutItem.type, localizedTitle: titleTextField.text ?? "", localizedSubtitle: subtitleTextField.text, icon: icon, userInfo: [
                    AppDelegate.applicationShortcutUserInfoIconKey: pickerView.selectedRowInComponent(0)
                ]
            )
        }
    }
}
